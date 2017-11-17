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

#include "lwip/err.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"
#include "lwip/netdb.h"
#include "lwip/dns.h"

#include "mruby.h"
#include "mruby/error.h"
#include "mruby/string.h"
#include "mruby/data.h"
#define TAG "mesp-loop"

typedef struct {
  mrb_value cb;
  mrb_value data;
} mruby_esp32_loop_event_t;

typedef struct {
	bool          init;
	int           ai;
	QueueHandle_t event_queue;
	TaskHandle_t  task;
	mrb_state*    mrb;
} mruby_esp32_loop_env_t;

static mruby_esp32_loop_env_t mruby_esp32_loop_env;

const int CONNECTED_BIT = BIT0;

static EventGroupHandle_t wifi_event_group;


void mruby_esp32_loop_data_env(mrb_state* mrb, mrb_value data, void* _t, mruby_esp32_loop_env_t** env) {
  Data_Get_Struct(mrb, data, NULL, *env);
}

static void mruby_esp32_loop_send_event_full(mruby_esp32_loop_event_t* event, bool isr, bool priority) {
	if (priority == TRUE) {
	  if(isr && (mruby_esp32_loop_env.init)) {
		xQueueSendToFrontFromISR(mruby_esp32_loop_env.event_queue, event, NULL);
  	  } else {
		xQueueSendToFront(mruby_esp32_loop_env.event_queue, event, portMAX_DELAY);
	  }		
    } else {
	  if(isr && (mruby_esp32_loop_env.init)) {
		xQueueSendToBackFromISR(mruby_esp32_loop_env.event_queue, event, NULL);
	  } else {
		xQueueSendToBack(mruby_esp32_loop_env.event_queue, event, portMAX_DELAY);
	  }
	}
}

static void mruby_esp32_loop_send_event_priority(mruby_esp32_loop_event_t* event, bool isr) {
  mruby_esp32_loop_send_event_full(event, isr, TRUE);
}

static void mruby_esp32_loop_send_event(mruby_esp32_loop_event_t* event, bool isr) {
  mruby_esp32_loop_send_event_full(event, isr, FALSE);  
}

static void mruby_esp32_loop_process_event(mrb_state* mrb, mruby_esp32_loop_event_t* event) { 	
 	if (!mrb_nil_p(event->cb)) {
	  int ai = mrb_gc_arena_save(mrb);
      mrb_funcall_argv(mrb, event->cb, mrb_intern_cstr(mrb, "call"), 1, &event->data); 
      mrb_gc_arena_restore(mrb, ai);	
    }	
}

static int mruby_esp32_loop_poll_event(mrb_state* mrb) {
	mruby_esp32_loop_event_t event;
	
	if (mruby_esp32_loop_env.event_queue != NULL) {
	  if(xQueueReceive(mruby_esp32_loop_env.event_queue, &event, 0)) {
		mruby_esp32_loop_process_event(mrb,&event);
		return 1;
	  }
    }
	return 0;
}

static mrb_value mruby_esp32_loop_get_event(mrb_state* mrb, mrb_value self) {
    mruby_esp32_loop_poll_event(mrb);
    return self;
}

static mrb_value mruby_esp32_loop_task_yield(mrb_state* mrb, mrb_value self) {
	taskYIELD();
	
	return self;
}

static void mruby_esp32_loop_init(mrb_state* mrb) {
    mruby_esp32_loop_env.task        = xTaskGetCurrentTaskHandle();
    mruby_esp32_loop_env.event_queue = xQueueCreate( 3, sizeof(mruby_esp32_loop_event_t));
    mruby_esp32_loop_env.init        = TRUE;
       
}

static mrb_value mruby_esp32_loop_app_run(mrb_state* mrb, mrb_value self) {
	mrb_value app;
	mrb_get_args(mrb, "&", &app);
    mruby_esp32_loop_env.ai = mrb_gc_arena_save(mrb);
	
    while (1) {
	  mrb_funcall(mrb, app, "call", 0);

	  //is exception occure?
	  if (mrb->exc){
		  // Serial.println("failed to run!");
		  // print_exception(mrb);
		  mrb->exc = 0;
		  // delay(1000);
		  printf("err\n");
	  }

	  mrb_gc_arena_restore(mrb,mruby_esp32_loop_env.ai);
	}
	
	return mrb_nil_value();
}

static mrb_value mruby_esp32_loop_printfd(mrb_state* mrb, mrb_value self) {
	mrb_int i;
	mrb_get_args(mrb, "i", &i);
	
	printf("%d", (int)i);

	return mrb_nil_value();
}

static mrb_value mruby_esp32_loop_printff(mrb_state* mrb, mrb_value self) {
	mrb_float f;
	mrb_get_args(mrb, "f", &f);
	
	printf("%f", (float)f);

	return mrb_nil_value();
}

static mrb_value mruby_esp32_loop_printfs(mrb_state* mrb, mrb_value self) {
	mrb_value s;
	mrb_get_args(mrb, "S", &s);
	int ai = mrb_gc_arena_save(mrb);
	printf("%s", mrb_string_value_cstr(mrb,&s));
    mrb_gc_arena_restore(mrb,ai);
	return mrb_nil_value();
}

static mrb_value mruby_esp32_loop_free(mrb_state* mrb, mrb_value self) {
  mrb_value t;
  mrb_get_args(mrb, "o", &t);
  struct mrb_time* tm = NULL;
  tm = (struct mrb_time*)DATA_PTR(t);
  if (tm) {
    mrb_free(mrb, tm);
  }
  return mrb_nil_value();
}

static esp_err_t 
mruby_esp32_loop_wifi_event_cb(void *ctx, system_event_t *event)
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
mruby_esp32_loop_wifi_connect(mrb_state *mrb, mrb_value self) {
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

static mrb_value mruby_esp32_loop_wifi_get_ip(mrb_state* mrb, mrb_value self) {
	if ((xEventGroupGetBits(wifi_event_group) & CONNECTED_BIT) != 0) {
      tcpip_adapter_ip_info_t ip_info;
      ESP_ERROR_CHECK(tcpip_adapter_get_ip_info(TCPIP_ADAPTER_IF_STA, &ip_info));
      return mrb_str_new_cstr(mrb, ip4addr_ntoa(&ip_info.ip));
    }
    
    return mrb_nil_value();
}

static mrb_value mruby_esp32_loop_wifi_has_ip(mrb_state* mrb, mrb_value self) {
	if ((xEventGroupGetBits(wifi_event_group) & CONNECTED_BIT) != 0) {
      return mrb_true_value();
    }
    
    return mrb_nil_value();
}

static mrb_value mruby_esp32_loop_stack_watermark(mrb_state* mrb, mrb_value self) {
	return mrb_fixnum_value(uxTaskGetStackHighWaterMark(mruby_esp32_loop_env.task));
}

void
mrb_mruby_esp32_loop_gem_init(mrb_state* mrb)
{
  esp_log_level_set("wifi", ESP_LOG_NONE); // disable wifi driver logging	
	
  mruby_esp32_loop_env.init        = FALSE;
  mruby_esp32_loop_env.event_queue = NULL;	

  mruby_esp32_loop_init(mrb);
  
  wifi_event_group = xEventGroupCreate();
  tcpip_adapter_init();
  ESP_ERROR_CHECK( esp_event_loop_init(mruby_esp32_loop_wifi_event_cb, NULL) );  
    
  
  struct RClass *esp32, *constants;
    
  esp32 = mrb_define_module(mrb, "ESP32");
	
  mrb_define_const(mrb, mrb->object_class, "ENV",  mrb_obj_value(Data_Wrap_Struct(mrb, mrb->object_class, NULL, &mruby_esp32_loop_env)));

  mrb_define_module_function(mrb, esp32, "app_run", mruby_esp32_loop_app_run, MRB_ARGS_NONE());  
  mrb_define_module_function(mrb, esp32, "free", mruby_esp32_loop_free, MRB_ARGS_REQ(1));    	
  mrb_define_module_function(mrb, esp32, "event?", mruby_esp32_loop_get_event, MRB_ARGS_NONE());      
  mrb_define_module_function(mrb, esp32, "yield!", mruby_esp32_loop_task_yield, MRB_ARGS_NONE());    
//  mrb_define_module_function(mrb, esp32, "log",    mruby_esp32_loop_log, MRB_ARGS_REQ(1));       
  mrb_define_module_function(mrb, esp32, "printfs",    mruby_esp32_loop_printfs, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, esp32, "printff",    mruby_esp32_loop_printff, MRB_ARGS_REQ(1));
  mrb_define_module_function(mrb, esp32, "printfd",    mruby_esp32_loop_printfd, MRB_ARGS_REQ(1));    
  mrb_define_module_function(mrb, esp32, "__wifi_connect__",  mruby_esp32_loop_wifi_connect, MRB_ARGS_REQ(2)); 
  mrb_define_module_function(mrb, esp32, "wifi_get_ip",       mruby_esp32_loop_wifi_get_ip, MRB_ARGS_NONE());   
  mrb_define_module_function(mrb, esp32, "wifi_has_ip?",      mruby_esp32_loop_wifi_has_ip, MRB_ARGS_NONE());   
  mrb_define_module_function(mrb, esp32, "watermark",         mruby_esp32_loop_stack_watermark, MRB_ARGS_NONE());    


  constants = mrb_define_module_under(mrb, esp32, "Constants");

#define define_const(SYM) \
  do { \
    mrb_define_const(mrb, constants, #SYM, mrb_fixnum_value(SYM)); \
  } while (0)

  mrb_define_const(mrb, constants, "PORT_MAX_DELAY",      mrb_fixnum_value(portMAX_DELAY));
  mrb_define_const(mrb, constants, "PORT_TICK_RATE_MS",   mrb_fixnum_value(portTICK_RATE_MS));
  mrb_define_const(mrb, constants, "PORT_TICK_PERIOD_MS", mrb_fixnum_value(portTICK_PERIOD_MS));
}

void
mrb_mruby_esp32_loop_gem_final(mrb_state* mrb)
{
}