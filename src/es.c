#include <stdio.h>
#include <string.h>

#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/timers.h>
#include "freertos/task.h"
#include "esp_system.h"
#include "esp_log.h"

#include "string.h"
#include "freertos/event_groups.h"

#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event_loop.h"

#include "esp_request.h"

#include "mruby.h"
#include "mruby/error.h"
#include "mruby/string.h"
#include "mruby/data.h"
#include "mruby/variable.h"
#include "mruby/compile.h"
#include "nvs_flash.h"

#define TAG "mesp-loop"

const int CONNECTED_BIT = BIT0;

/* Event Queue EventType */
typedef struct {
  mrb_value cb;   // handler
  int       type; // event type
  int       len;  // optional, required for strings
  void*     data; // data
} mees_event_t;

/* Context */
typedef struct {
	bool          init;        // Initialized
	bool          run;         // Main loop running
	mrb_value     idle_cb;     // The idle event handler
	int           ai;          // Arena index at start
	QueueHandle_t event_queue; // Event queue
	TaskHandle_t  task;        // Task Handle
	mrb_state*    mrb;         // mrb_state*
} mees_env_t;

/* HTTP Request Event */
typedef struct {
	request_t* req; // request
	int len;        // length of data
	char* data;     // data recieved
} mees_http_event_t;

static mees_http_event_t  mees_http_event  = {0};  // HTTP Downloads block.
static mees_env_t         mees_env         = {0};  // context
static EventGroupHandle_t wifi_event_group;


void mees_data_env(mrb_state* mrb, mrb_value data, void* _t, mees_env_t** env) {
  Data_Get_Struct(mrb, data, NULL, *env);
}

void mees_data_req(mrb_state* mrb, mrb_value data, void* _t, request_t** req) {
  Data_Get_Struct(mrb, data, NULL, *req);
}


/* Events */

static void mees_event_send_full(mees_event_t* event, bool isr, bool priority) {
	if (priority == TRUE) {
	  if(isr && (mees_env.init)) {
		xQueueSendToFrontFromISR(mees_env.event_queue, event, NULL);
  	  } else {
		xQueueSendToFront(mees_env.event_queue, event, portMAX_DELAY);
	  }		
    } else {
	  if(isr && (mees_env.init)) {
		xQueueSendToBackFromISR(mees_env.event_queue, event, NULL);
	  } else {
		xQueueSendToBack(mees_env.event_queue, event, portMAX_DELAY);
	  }
	}
}

static void mees_event_send_priority(mees_event_t* event, bool isr) {
  mees_event_send_full(event, isr, TRUE);
}

static void mees_event_send(mees_event_t* event, bool isr) {
  mees_event_send_full(event, isr, FALSE);  
}

static void mees_event_process_event(mrb_state* mrb, mees_event_t* event) { 	
 	if (!mrb_nil_p(event->cb)) {
	  int ai = mrb_gc_arena_save(mrb);
	  
	  mrb_value data;
	  
	  switch (event->type) {
		  case 0:
		    // data is Fixnum
		    data = mrb_fixnum_value((int)event->data);
		    break;
		  case 1:
		    // data is Float
		    data = mrb_float_value(mrb, *(float *)&event->data);
		    break;
		  case 2:
		    // data is String
		    data = mrb_str_new(mrb, (char*)event->data, event->len-1);
		    break;
		  default:
		    // None or unhandled data
		    data = mrb_nil_value();
		    break;		    		    
	  }

      mrb_funcall(mrb, event->cb, "call", 1, data); 
      
      event->data=(void*)"";
      
      mrb_gc_arena_restore(mrb, ai);	
    }	
}

static int mees_event_poll(mrb_state* mrb) {
	mees_event_t event;
	
	if (mees_env.event_queue != NULL) {
	  if(xQueueReceive(mees_env.event_queue, &event, 0)) {
		mees_event_process_event(mrb,&event);
		return 1;
	  }
    }
	return 0;
}

// allows to handle next event from idle loop
static mrb_value mruby_mees_event_next_event(mrb_state* mrb, mrb_value self) {
    if (1 == mees_event_poll(mrb)) {
		return mrb_true_value();
	}
    
    return mrb_nil_value();
}

// returns number of events pending
static mrb_value mruby_mees_event_pending_events(mrb_state* mrb, mrb_value self) {
		
  return mrb_fixnum_value(uxQueueMessagesWaiting(mees_env.event_queue));
}


/* Task */

static mrb_value mruby_mees_task_stack_watermark(mrb_state* mrb, mrb_value self) {
	return mrb_fixnum_value(uxTaskGetStackHighWaterMark(mees_env.task));
}

static mrb_value mruby_mees_task_yield(mrb_state* mrb, mrb_value self) {
	taskYIELD();
	
	return self;
}

static mrb_value mruby_mees_task_delay(mrb_state* mrb, mrb_value self) {
  mrb_int delay;
  mrb_get_args(mrb, "i", &delay);

  vTaskDelay(delay / portTICK_PERIOD_MS);

  return self;
}



/* Main Loop */

// a call back to perform when idle
// any object responding to 'call'
static mrb_value mruby_mees_on_idle(mrb_state* mrb, mrb_value self) {
	mrb_value idle;
	mrb_get_args(mrb, "o", &idle);
	
	mrb_gc_protect(mrb,idle);
	
	mees_env.idle_cb = idle;
	
	return mrb_true_value();
}

// Enter the main loop
static mrb_value mruby_mees_main(mrb_state* mrb, mrb_value self) {
	mees_env.ai  = mrb_gc_arena_save(mrb);
	mees_env.run = TRUE;
	
    while (mees_env.run) {
	  if (mees_event_poll(mrb) == 0) {
	    if (!mrb_nil_p(mees_env.idle_cb)) {
	      // Dispatch idle event
	      mrb_funcall(mrb, mees_env.idle_cb, "call", 0);
	    }
	  } else {
         // Event was handled
      }
      
	  mrb_gc_arena_restore(mrb,mees_env.ai);
	}
	
	// Main loop ended;
	
	return mrb_nil_value();
}

// Return from main loop
static mrb_value mruby_mees_main_quit(mrb_state* mrb, mrb_value self) {
	mees_env.run = FALSE;
	
	return mrb_nil_value();
}

/* Time */
static mrb_value mruby_mees_set_time(mrb_state* mrb, mrb_value self) {
	mrb_int seconds;
	mrb_int usecs;
	
	mrb_get_args(mrb, "ii", &seconds, &usecs);

    struct timeval tv;
    tv.tv_sec  = seconds;
    tv.tv_usec = usecs;

    settimeofday(&tv, NULL);
    
    return self;
}

/* WiFi */

static esp_err_t 
mees_wifi_event_cb(void *ctx, system_event_t *event)
{
  switch(event->event_id) {
    case SYSTEM_EVENT_STA_START:
      esp_wifi_connect();
      break;
    case SYSTEM_EVENT_STA_GOT_IP:
      xEventGroupSetBits(wifi_event_group, CONNECTED_BIT);
      break;
    case SYSTEM_EVENT_STA_DISCONNECTED:
      // This is a workaround as ESP32 WiFi libs don't currently auto-reassociate. 
      xEventGroupClearBits(wifi_event_group, CONNECTED_BIT);
      esp_wifi_connect();
      break;
    default:
      break;
  }
  return ESP_OK;
}

static mrb_value
mruby_mees_wifi_connect(mrb_state *mrb, mrb_value self) {
  char *ssid = NULL;
  char *password = NULL;

  mrb_get_args(mrb, "zz", &ssid, &password);

  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK( esp_wifi_init(&cfg) );
  ESP_ERROR_CHECK( esp_wifi_set_storage(WIFI_STORAGE_RAM) );

  wifi_config_t wifi_config = {0};
  //memset((void *)&wifi_config, 0, sizeof(wifi_config_t));
  snprintf(wifi_config.sta.ssid, sizeof(wifi_config.sta.ssid), "%s", ssid);
  snprintf(wifi_config.sta.password, sizeof(wifi_config.sta.password), "%s", password);

  ESP_ERROR_CHECK( esp_wifi_set_mode(WIFI_MODE_STA) );
  ESP_ERROR_CHECK( esp_wifi_set_config(WIFI_IF_STA, &wifi_config) );
  ESP_ERROR_CHECK( esp_wifi_start() );

  return self;
}

static mrb_value mruby_mees_wifi_get_ip(mrb_state* mrb, mrb_value self) {
	if ((xEventGroupGetBits(wifi_event_group) & CONNECTED_BIT) != 0) {
      tcpip_adapter_ip_info_t ip_info;
      ESP_ERROR_CHECK(tcpip_adapter_get_ip_info(TCPIP_ADAPTER_IF_STA, &ip_info));
      return mrb_str_new_cstr(mrb, ip4addr_ntoa(&ip_info.ip));
    }
    
    return mrb_nil_value();
}

static mrb_value mruby_mees_wifi_has_ip(mrb_state* mrb, mrb_value self) {
	if ((xEventGroupGetBits(wifi_event_group) & CONNECTED_BIT) != 0) {
      tcpip_adapter_ip_info_t ip_info;
      ESP_ERROR_CHECK(tcpip_adapter_get_ip_info(TCPIP_ADAPTER_IF_STA, &ip_info));
      return mrb_true_value();
    }
    
    return mrb_nil_value();

}

/* HTTP */

int mees_http_callback(request_t *req, char* data, int len) {
	mees_http_event.req  = req;
	mees_http_event.data = data;
	mees_http_event.len  = len;
	
	return 0;
}

static mrb_value mruby_mees_http_get(mrb_state* mrb, mrb_value self) {
	mees_http_event.data="";
	mees_http_event.len = 0;
	
    mrb_value uri, cb;
    mrb_get_args(mrb, "S&",&uri,&cb);
    int ai = mrb_gc_arena_save(mrb);
  
    request_t *req = req_new(mrb_string_value_cstr(mrb, &uri));
    req_setopt(req, REQ_SET_METHOD, "GET");
    req_setopt(req, REQ_FUNC_DOWNLOAD_CB, mees_http_callback);
    int status = req_perform(req);
    req_clean(req);	
   
    mrb_funcall(mrb, cb, "call", 1, mrb_str_new_cstr(mrb, mees_http_event.data));
    
    mrb_gc_arena_restore(mrb,ai);
    
    return mrb_fixnum_value(status);
}

static mrb_value mruby_mees_http_post(mrb_state* mrb, mrb_value self) {
    /*request_t *req = req_new(uri)
    req_setopt(req, REQ_SET_METHOD, "POST");
    req_setopt(req, REQ_SET_POSTFIELDS, mrb_string_value_cstr(&flds));
    req_setopt(req, REQ_FUNC_DOWNLOAD_CB, download_callback);
    status = req_perform(req);
    req_clean(req);	*/
    
    return mrb_nil_value();
}

/* WebSocket */

static int mees_ws_cb(request_t *req, int status, void *buffer, int len)
{
	mees_event_t* evt = (mees_event_t*)req->context;
	
	bool send=TRUE;
	
    switch(status) {
        case WS_CONNECTED:
            evt->type=0;
            evt->data=0;
            break;
        case WS_DATA:
            ((char*)buffer)[len] = 0;
            
            evt->type = 2;
            evt->data = buffer; 
            evt->len  = len+1;

            break;
        case WS_DISCONNECTED:
            evt->type=0;
            evt->data=1;
            req_clean(req);
            req = NULL;
            break;
        default:
            send=FALSE;
    }
    
    if (send) {
      mees_event_send(evt, FALSE);
	}
	
    return 0;
}

static mrb_value mruby_mees_ws_new(mrb_state* mrb, mrb_value self) {
	mrb_value cb;
	char* host;
	mrb_get_args(mrb, "z&", &host, &cb);
	
	mrb_gc_protect(mrb,cb);
	
	static mees_event_t evt = {0};
	evt.cb   = cb;
 
    request_t *req = req_new(host); 
    req->context = (void*)&evt;
    
    req_setopt(req, REQ_FUNC_WEBSOCKET, mees_ws_cb);
    req_perform(req);	
	
	return mrb_obj_value(Data_Wrap_Struct(mrb, mrb->object_class, NULL, req));
}

static mrb_value mruby_mees_ws_write(mrb_state* mrb, mrb_value self) {
	mrb_value ins;
	char* str;
	mrb_int len;
	
	mrb_get_args(mrb, "os", &ins,&str,&len);
	
	request_t* req;
	mees_data_req(mrb,ins,NULL,&req);
	
	req_write(req,str,(int)len);
	
	return ins;
}

static mrb_value mruby_mees_ws_close(mrb_state* mrb, mrb_value self) {
	mrb_value ins;
	
	mrb_get_args(mrb, "o", &ins);
	
	request_t* req;
	mees_data_req(mrb,ins,NULL,&req);
	
	req_clean(req);
	
	return mrb_nil_value();
}

/* eval */

static mrb_value mruby_mees_eval(mrb_state* mrb, mrb_value self) {
	char* code;
	
	mrb_get_args(mrb, "z", &code);
	int ai = mrb_gc_arena_save(mrb);
	mrb_value res=mrb_load_string(mrb, code);
	mrb_gc_arena_restore(mrb,ai);
	
	return mrb_funcall(mrb, res, "inspect", 0);
}

/* TCP Client */

static mrb_value mruby_mees_tcp_client_new(mrb_state* mrb, mrb_value self) {
    char* ip;
    mrb_int port;
    int s;
    mrb_get_args(mrb, "zi", &ip, &port);
    
    struct sockaddr_in tcpServerAddr;
    tcpServerAddr.sin_addr.s_addr = inet_addr(ip);
    tcpServerAddr.sin_family = AF_INET;
    tcpServerAddr.sin_port = htons( port );

    s = socket(AF_INET, SOCK_STREAM, 0);
    if(s < 0) {
      ESP_LOGE(TAG, "... Failed to allocate socket.\n");
      return mrb_nil_value();
    }
    
    if(connect(s, (struct sockaddr *)&tcpServerAddr, sizeof(tcpServerAddr)) != 0) {
      ESP_LOGE(TAG, "... socket connect failed errno=%d \n", errno);
      close(s);
      return mrb_nil_value();
    }
    
    return mrb_fixnum_value(s);
}

/* IO */

static mrb_value mruby_mees_io_write(mrb_state* mrb, mrb_value self) {
	char* msg;
	mrb_int fd;
	mrb_get_args(mrb, "iz", &fd, &msg);
	
    if( write(fd , msg , strlen(msg)) < 0) {
      ESP_LOGE(TAG, "... Send failed \n");
      close(fd);
      return mrb_nil_value();
    }
    
    return mrb_true_value();
}

static mrb_value mruby_mees_io_recv_nonblock(mrb_state* mrb, mrb_value self) {
	mrb_int fd, len;
	
	mrb_get_args(mrb, "ii", &fd, &len);
	
	int r;
	char recv_buf[len];
	
	bzero(recv_buf, sizeof(recv_buf));
	
	r = recv(fd, recv_buf, sizeof(recv_buf)-1, MSG_DONTWAIT);
	
	if (r > 0) {
	  return mrb_str_new_cstr(mrb, (char*)recv_buf);
	}

    return mrb_nil_value();
}

static mrb_value mruby_mees_io_close(mrb_state* mrb, mrb_value self) {
	mrb_int fd;
	mrb_get_args(mrb, "i", &fd);
	
	close(fd);
	
	return mrb_true_value();
}

/* internal */

static void 
mees_init(mrb_state* mrb) {
    mees_env.task        = xTaskGetCurrentTaskHandle();
    mees_env.event_queue = xQueueCreate( 10, sizeof(mees_event_t));
    mees_env.init        = TRUE;
    mees_env.idle_cb     = mrb_nil_value();
    mees_env.run         = FALSE;
}

void 
mees_setup(mrb_state* mrb) {
  esp_log_level_set("wifi", ESP_LOG_NONE);
  esp_log_level_set("HTTP_REQ", ESP_LOG_NONE);	
 
  mees_env.init        = FALSE;
  mees_env.event_queue = NULL;	

  mees_init(mrb);
  
  wifi_event_group = xEventGroupCreate();
 
  tcpip_adapter_init();
 
  ESP_ERROR_CHECK( esp_event_loop_init(mees_wifi_event_cb, NULL) );  	
}

void
mrb_mruby_esp32_es_gem_init(mrb_state* mrb)
{
  mees_setup(mrb);
  
  struct RClass *mees, *port;
    
  mees = mrb_define_module(mrb, "MEES");
	
  // Main Loop
  mrb_define_module_function(mrb, mees, "main__on_idle",  mruby_mees_on_idle,   MRB_ARGS_NONE());  // Idle Event 
  mrb_define_module_function(mrb, mees, "main__run",      mruby_mees_main,      MRB_ARGS_NONE());  // Start
  mrb_define_module_function(mrb, mees, "main_quit",      mruby_mees_main_quit, MRB_ARGS_NONE());  // End

  // Events
  mrb_define_module_function(mrb, mees, "event_next_event",     mruby_mees_event_next_event,     MRB_ARGS_NONE()); // Returns true if an event was processed      
  mrb_define_module_function(mrb, mees, "event_pending_events", mruby_mees_event_pending_events, MRB_ARGS_NONE()); // n Events pending
  
  // Simple eval
  mrb_define_module_function(mrb, mees, "eval",          mruby_mees_eval,     MRB_ARGS_REQ(1)); // run some code

  // Time
  mrb_define_module_function(mrb, mees, "time_set_time", mruby_mees_set_time, MRB_ARGS_REQ(2)); // sets time

  // task
  mrb_define_module_function(mrb, mees, "task_yield",           mruby_mees_task_yield, MRB_ARGS_NONE());           // taskYEILD    
  mrb_define_module_function(mrb, mees, "task_stack_watermark", mruby_mees_task_stack_watermark, MRB_ARGS_NONE()); // Least amount of stack for task
  mrb_define_module_function(mrb, mees, "task_delay",           mruby_mees_task_delay, MRB_ARGS_REQ(1));           // vTaskDelay(i)   

  // WiFi
  mrb_define_module_function(mrb, mees, "wifi__connect", mruby_mees_wifi_connect, MRB_ARGS_REQ(2)); 
  mrb_define_module_function(mrb, mees, "wifi_get_ip",   mruby_mees_wifi_get_ip, MRB_ARGS_NONE());   
  mrb_define_module_function(mrb, mees, "wifi_has_ip?",  mruby_mees_wifi_has_ip, MRB_ARGS_NONE());   

  // WebSocket Client
  mrb_define_module_function(mrb, mees, "ws_write", mruby_mees_ws_write, MRB_ARGS_REQ(2)); 
  mrb_define_module_function(mrb, mees, "ws_close", mruby_mees_ws_close, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, mees, "ws_new",   mruby_mees_ws_new,   MRB_ARGS_NONE());   

  // HTTP Client
  mrb_define_module_function(mrb, mees, "http_get",  mruby_mees_http_get,  MRB_ARGS_REQ(1));     
  // mrb_define_module_function(mrb, mees, "http_post", mruby_mees_http_post, MRB_ARGS_REQ(1));  
  
  // TCP Client
  mrb_define_module_function(mrb, mees, "tcp_client_new",   mruby_mees_tcp_client_new,   MRB_ARGS_REQ(2));
  
  // IO
  mrb_define_module_function(mrb, mees, "io_write",         mruby_mees_io_write,         MRB_ARGS_REQ(2));
  mrb_define_module_function(mrb, mees, "io_recv_nonblock", mruby_mees_io_recv_nonblock, MRB_ARGS_REQ(2));  
  mrb_define_module_function(mrb, mees, "io_close",         mruby_mees_io_close,         MRB_ARGS_REQ(1)); 


  // Constants
  port = mrb_define_module_under(mrb, mees, "Port");

  mrb_define_const(mrb, port, "MAX_DELAY",      mrb_fixnum_value(portMAX_DELAY));
  mrb_define_const(mrb, port, "TICK_RATE_MS",   mrb_fixnum_value(portTICK_RATE_MS));
  mrb_define_const(mrb, port, "TICK_PERIOD_MS", mrb_fixnum_value(portTICK_PERIOD_MS));
}

void
mrb_mruby_esp32_es_gem_final(mrb_state* mrb)
{
}
