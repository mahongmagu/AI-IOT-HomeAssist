```
curl -X POST http://localhost:3002/api/ai \
  -H "Content-Type: application/json" \
  -d 
'{
    "text": "关闭保姆间的开关"
  }'
```

同样错误

```
curl -X POST http://localhost:3002/api/ai \
  -H "Content-Type: application/json" \
  -d '{
    "text": "关闭保姆间扫地机的开关"
  }'
```

同样错误



```
curl -v http://localhost:3002/api/config
```

*   Trying 127.0.0.1:3002...
* Connected to localhost (127.0.0.1) port 3002 (#0)
> GET /api/config HTTP/1.1
> Host: localhost:3002
> User-Agent: curl/7.81.0
> Accept: */*
>
* Mark bundle as not supporting multiuse
< HTTP/1.1 200 OK
< X-Powered-By: Express
< RateLimit-Policy: 400;w=900
< RateLimit-Limit: 400
< RateLimit-Remaining: 399
< RateLimit-Reset: 866
< Access-Control-Allow-Origin: *
< Content-Type: application/json; charset=utf-8
< Content-Length: 1710
< ETag: W/"6ae-5RIHjVmfgzqq//ZS/YRw3p/IAg0"
< Date: Sat, 09 May 2026 03:03:02 GMT
< Connection: keep-alive
< Keep-Alive: timeout=5
< 
{"code":200,"configs":{"sdj":{"name":"sdj","displayName":"扫地机","id":"baomujian-sdj-40858013","location":"保姆间","units":[{"id":"baomujian-sdj-40858013_kaiguan-2966","name":"开关","status":"OFF","type":"control"}]},"shg":{"name":"shg","displayName":"珊瑚缸","id":"keting-shg-64771774","location":"客厅","units":[{"id":"keting-shg-64771774_fengshan-0838","name":"风扇","status":"OFF","type":"control"},{"id":"keting-shg-64771774_yangqi-0041","name":"氧气","status":"OFF","type":"control"},{"id":"keting-shg-64771774_weishi-3278","name":"喂食","status":"OFF","type":"control"},{"id":"keting-shg-64771774_gongshui-5747","name":"供水","status":"OFF","type":"control"},{"id":"keting-shg-64771774_gaoshuiweichuanganqi-5209","name":"高水位传感器","status":"ON","type":"state"},{"id":"keting-shg-64771774_dishuiweichuanganqi-9611","name":"低水位传感器","status":"ON","type":"state"},{"id":"keting-shg-64771774_wenduchuanganqi-5906","name":"温度传感器","status":"27","type":"state"},{"id":"ke* Connection #0 to host localhost left intact
ting-shg-64771774_wendushangxianzhi-3641","name":"温度上限值","status":"31","type":"data"},{"id":"keting-shg-64771774_wenduxiaxianzhi-1602","name":"温度下线值","status":"26","type":"data"}]},"test":{"name":"test","displayName":"测试设备","id":"0000-test-16337710","location":null,"units":[{"id":"0000-test-16337710_kaiguan-3871","name":"开关","status":"OFF","type":"control"},{"id":"0000-test-16337710_zhuangtai-1151","name":"状态","status":"ON","type":"state"},{"id":"0000-test-16337710_wenben-4757","name":"文本","status":"上帝","type":"text"},{"id":"0000-test-16337710_shuzi-8879","name":"数字","status":"0","type":"data"}]}},"wsPort":"8090","apiBase":"/api"}



```
curl -X POST http://localhost:3002/api/control \
  -H "Content-Type: application/json" \
  -d '{
    "unitId": "baomujian-sdj-40858013_kaiguan-2966",
    "cmd": "OFF"                                    
  }'
```

{"code":400,"msg":"缺少必要的设备参数：deviceType, deviceId, category, unitId, unitType"}



- ```
  curl http://localhost:3002/api/status |python3 -m json.tool
  ```

    % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                   Dload  Upload   Total   Spent    Left  Speed
  100  2327  100  2327    0     0   192k      0 --:--:-- --:--:-- --:--:--  227k
  {
      "code": 200,
      "mqttConnected": true,
      "states": {
          "baomujian-sdj-40858013_kaiguan-2966": "OFF",
          "keting-shg-64771774_fengshan-0838": "OFF",
          "keting-shg-64771774_yangqi-0041": "OFF",
          "keting-shg-64771774_weishi-3278": "OFF",
          "keting-shg-64771774_gongshui-5747": "OFF",
          "keting-shg-64771774_gaoshuiweichuanganqi-5209": "ON",
          "keting-shg-64771774_dishuiweichuanganqi-9611": "ON",
          "keting-shg-64771774_wenduchuanganqi-5906": "27",
          "keting-shg-64771774_wendushangxianzhi-3641": "31",
          "keting-shg-64771774_wenduxiaxianzhi-1602": "26",
          "0000-test-16337710_kaiguan-3871": "OFF",
          "0000-test-16337710_zhuangtai-1151": "ON",
          "0000-test-16337710_wenben-4757": "\u4e0a\u5e1d",
          "0000-test-16337710_shuzi-8879": "0"
      },
      "configs": {
          "sdj": {
              "name": "sdj",
              "displayName": "\u626b\u5730\u673a",
              "id": "baomujian-sdj-40858013",
              "location": "\u4fdd\u59c6\u95f4",
              "units": [
                  {
                      "id": "baomujian-sdj-40858013_kaiguan-2966",
                      "name": "\u5f00\u5173",
                      "status": "OFF",
                      "type": "control"
                  }
              ]
          },
          "shg": {
              "name": "shg",
              "displayName": "\u73ca\u745a\u7f38",
              "id": "keting-shg-64771774",
              "location": "\u5ba2\u5385",
              "units": [
                  {
                      "id": "keting-shg-64771774_fengshan-0838",
                      "name": "\u98ce\u6247",
                      "status": "OFF",
                      "type": "control"
                  },
                  {
                      "id": "keting-shg-64771774_yangqi-0041",
                      "name": "\u6c27\u6c14",
                      "status": "OFF",
                      "type": "control"
                  },
                  {
                      "id": "keting-shg-64771774_weishi-3278",
                      "name": "\u5582\u98df",
                      "status": "OFF",
                      "type": "control"
                  },
                  {
                      "id": "keting-shg-64771774_gongshui-5747",
                      "name": "\u4f9b\u6c34",
                      "status": "OFF",
                      "type": "control"
                  },
                  {
                      "id": "keting-shg-64771774_gaoshuiweichuanganqi-5209",
                      "name": "\u9ad8\u6c34\u4f4d\u4f20\u611f\u5668",
                      "status": "ON",
                      "type": "state"
                  },
                  {
                      "id": "keting-shg-64771774_dishuiweichuanganqi-9611",
                      "name": "\u4f4e\u6c34\u4f4d\u4f20\u611f\u5668",
                      "status": "ON",
                      "type": "state"
                  },
                  {
                      "id": "keting-shg-64771774_wenduchuanganqi-5906",
                      "name": "\u6e29\u5ea6\u4f20\u611f\u5668",
                      "status": "27",
                      "type": "state"
                  },
                  {
                      "id": "keting-shg-64771774_wendushangxianzhi-3641",
                      "name": "\u6e29\u5ea6\u4e0a\u9650\u503c",
                      "status": "31",
                      "type": "data"
                  },
                  {
                      "id": "keting-shg-64771774_wenduxiaxianzhi-1602",
                      "name": "\u6e29\u5ea6\u4e0b\u7ebf\u503c",
                      "status": "26",
                      "type": "data"
                  }
              ]
          },
          "test": {
              "name": "test",
              "displayName": "\u6d4b\u8bd5\u8bbe\u5907",
              "id": "0000-test-16337710",
              "location": null,
              "units": [
                  {
                      "id": "0000-test-16337710_kaiguan-3871",
                      "name": "\u5f00\u5173",
                      "status": "OFF",
                      "type": "control"
                  },
                  {
                      "id": "0000-test-16337710_zhuangtai-1151",
                      "name": "\u72b6\u6001",
                      "status": "ON",
                      "type": "state"
                  },
                  {
                      "id": "0000-test-16337710_wenben-4757",
                      "name": "\u6587\u672c",
                      "status": "\u4e0a\u5e1d",
                      "type": "text"
                  },
                  {
                      "id": "0000-test-16337710_shuzi-8879",
                      "name": "\u6570\u5b57",
                      "status": "0",
                      "type": "data"
                  }
              ]
          }
      }
  }

  设备UUID在列表中

  

  ```
  curl http://localhost:3002/api/status | grep -A 5 "baomujian-sdj-40858013_kaiguan-2966"
    % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
  ```

  ​                                 Dload  Upload   Total   Spent    Left  Speed
  100  2327  100  2327    0     0   200k      0 --:--:-- --:--:-- --:--:--  227k
  {"code":200,"mqttConnected":true,"states":{"baomujian-sdj-40858013_kaiguan-2966":"OFF","keting-shg-64771774_fengshan-0838":"OFF","keting-shg-64771774_yangqi-0041":"OFF","keting-shg-64771774_weishi-3278":"OFF","keting-shg-64771774_gongshui-5747":"OFF","keting-shg-64771774_gaoshuiweichuanganqi-5209":"ON","keting-shg-64771774_dishuiweichuanganqi-9611":"ON","keting-shg-64771774_wenduchuanganqi-5906":"27","keting-shg-64771774_wendushangxianzhi-3641":"31","keting-shg-64771774_wenduxiaxianzhi-1602":"26","0000-test-16337710_kaiguan-3871":"OFF","0000-test-16337710_zhuangtai-1151":"ON","0000-test-16337710_wenben-4757":"上帝","0000-test-16337710_shuzi-8879":"0"},"configs":{"sdj":{"name":"sdj","displayName":"扫地机","id":"baomujian-sdj-40858013","location":"保姆间","units":[{"id":"baomujian-sdj-40858013_kaiguan-2966","name":"开关","status":"OFF","type":"control"}]},"shg":{"name":"shg","displayName":"珊瑚缸","id":"keting-shg-64771774","location":"客厅","units":[{"id":"keting-shg-64771774_fengshan-0838","name":"风扇","status":"OFF","type":"control"},{"id":"keting-shg-64771774_yangqi-0041","name":"氧气","status":"OFF","type":"control"},{"id":"keting-shg-64771774_weishi-3278","name":"喂食","status":"OFF","type":"control"},{"id":"keting-shg-64771774_gongshui-5747","name":"供水","status":"OFF","type":"control"},{"id":"keting-shg-64771774_gaoshuiweichuanganqi-5209","name":"高水位传感器","status":"ON","type":"state"},{"id":"keting-shg-64771774_dishuiweichuanganqi-9611","name":"低水位传感器","status":"ON","type":"state"},{"id":"keting-shg-64771774_wenduchuanganqi-5906","name":"温度传感器","status":"27","type":"state"},{"id":"keting-shg-64771774_wendushangxianzhi-3641","name":"温度上限值","status":"31","type":"data"},{"id":"keting-shg-64771774_wenduxiaxianzhi-1602","name":"温度下线值","status":"26","type":"data"}]},"test":{"name":"test","displayName":"测试设备","id":"0000-test-16337710","location":null,"units":[{"id":"0000-test-16337710_kaiguan-3871","name":"开关","status":"OFF","type":"control"},{"id":"0000-test-16337710_zhuangtai-1151","name":"状态","status":"ON","type":"state"},{"id":"0000-test-16337710_wenben-4757","name":"文本","status":"上帝","type":"text"},{"id":"0000-test-16337710_shuzi-8879","name":"数字","status":"0","type":"data"}]}}}

命令写入正常