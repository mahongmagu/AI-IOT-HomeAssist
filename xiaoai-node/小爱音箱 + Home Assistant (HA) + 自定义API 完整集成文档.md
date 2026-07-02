# 小爱音箱 \+ Home Assistant \(HA\) \+ 自定义API 完整集成文档

（可直接用于项目部署、从零搭建、问题排查，包含 **rest\_command** 和 **shell\_command** 双方案，适配Docker环境）

# 一、整体架构逻辑（核心）

## 1\. 完整执行流程（极简稳定版）

1. 对小爱音箱说话（例：“打开扫地机”“关闭扫地机”）；

2. 小爱音箱不执行本地米家设备控制（避免播报“没有设备”）；

3. 语音转文字，同步到HA的语音文字传感器（`sensor\.xiaomi\_l05b\_af0a\_conversation`）；

4. HA自动化触发，通过请求方式（rest\_command / shell\_command）发送文字指令到自定义API；

5. 自定义API接收指令，执行设备控制（如开关扫地机）；

6. HA调用小爱TTS播报自定义提示（“操作成功”），覆盖小爱原生报错。

## 2\. 网络环境说明

- HA宿主机IP：`192\.168\.1\.51`

- 自定义API服务IP\+端口：`192\.168\.1\.40:6002`

- HA容器运行方式：`\-\-net=host`（与宿主机同网络，避免局域网访问失败）

## 3\. 两种请求方式对比（核心差异）

|请求方式|优点|缺点|推荐程度|
|---|---|---|---|
|rest\_command（HA原生）|配置简单、原生组件、代码干净|Linux Docker \+ host网络下易出现超时BUG|❌ 不推荐（仅适配非Docker/特殊环境）|
|shell\_command（系统curl）|100%稳定、无超时、与系统curl执行一致|依赖系统curl命令（HA容器默认自带）|✅ 强烈推荐（解决Docker环境超时问题）|

# 二、环境要求（前置条件）

1. HA安装方式：Docker容器，且启动时添加 `\-\-net=host` 参数；

2. HA已安装集成：Xiaomi MIoT（自定义集成，用于接入小爱音箱）；

3. 小爱音箱已通过Xiaomi MIoT集成接入HA，可正常同步语音文字；

4. 自定义API服务可正常被局域网访问（宿主机、HA容器均可curl通）；

5. HA容器内已安装curl（默认自带，若没有可手动安装）。

# 三、完整配置文件（configuration\.yaml）

包含两种请求方式，可同时配置，按需启用（推荐仅保留shell\_command），直接复制覆盖HA的 `configuration\.yaml` 文件即可。

```yaml
default_config:

frontend:
  themes: !include_dir_merge_named themes

# ===========================
# 方案 A：rest_command（HA原生组件）
# 适用场景：非Docker环境、HA无网络BUG的场景
# ===========================
rest_command:
  xiaoai_api_request:      # 服务ID（自动化中调用时使用）
    url: "http://192.168.1.40:6002/api/ai-advanced"  # 自定义API地址
    method: POST           # 请求方式（固定POST，与API对应）
    headers:               # 请求头（固定JSON格式）
      Content-Type: "application/json"
    payload: '{"text":"{{ text }}"}'  # 发送的JSON内容，{{ text }} 是自动化传递的语音文字变量

# ===========================
# 方案 B：shell_command（推荐，解决Docker超时）
# 适用场景：Docker环境、rest_command超时的场景
# ===========================
shell_command:
  send_ai_request: 'curl -X POST http://192.168.1.40:6002/api/ai-advanced -H "Content-Type: application/json" -d ''{"text":"{{ text }}"}'''

# HA系统默认配置（请勿修改）
automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
```

# 四、详细配置说明（分方案）

## 方案1：rest\_command 配置详解

### 1\. 配置位置

必须放在 `configuration\.yaml` 根层级，与 `automation`、`shell\_command` 同级，不可嵌套在其他配置内。

### 2\. 核心参数解释

- `rest\_command`：固定关键字，用于定义HA原生REST请求服务；

- `xiaoai\_api\_request`：自定义服务ID，可修改（如 `ai\_advanced\_request`），自动化调用时需与该ID一致；

- `url`：自定义API的完整地址，必须是局域网可访问的真实IP（不可用 `host\.docker\.internal`，Linux不支持）；

- `method: POST`：固定为POST，与API的请求方式对应；

- `headers`：请求头，固定 `Content\-Type: application/json`，确保API能识别JSON格式的请求体；

- `payload`：请求体，JSON格式，`\{\{ text \}\}` 是变量，用于接收自动化传递的小爱语音文字。

### 3\. 注意事项

- payload的引号需用单引号包裹，内部JSON的引号用双引号，避免格式错误；

- 若API需要其他请求头（如token），可在 `headers` 下添加，例：`Authorization: \&\#34;Bearer xxx\&\#34;`；

- 配置完成后，需重启HA生效（`docker restart homeassistant`）。

## 方案2：shell\_command 配置详解

### 1\. 配置位置

与 `rest\_command` 同级，放在 `configuration\.yaml` 根层级。

### 2\. 核心参数解释

- `shell\_command`：固定关键字，用于定义HA调用系统shell命令；

- `send\_ai\_request`：自定义服务ID，自动化调用时需与该ID一致；

- 后面的curl命令：模拟系统curl发送POST请求，参数与rest\_command一致，其中 `\&\#39;\&\#39;\{\&\#34;text\&\#34;:\&\#34;\{\{ text \}\}\&\#34;\}\&\#39;\&\#39;` 用双单引号包裹，避免变量解析错误。

### 3\. 注意事项

- 若HA容器内没有curl，需先安装：`docker exec \-it homeassistant apk add curl`；

- curl命令需完整，不可遗漏 `\-H \&\#34;Content\-Type: application/json\&\#34;`，否则API可能无法识别请求体；

- 配置完成后，重启HA生效。

# 五、自动化配置（核心触发逻辑）

自动化是连接“小爱语音文字”与“API请求”的核心，需在HA的自动化编辑器中配置（不可直接写在 `configuration\.yaml` 内，避免格式报错）。

## 方案1：rest\_command 版自动化（不推荐）

路径：HA → 设置 → 自动化与场景 → 创建自动化 → 从YAML粘贴 → 保存生效

```yaml
alias: 小爱语音转发到AI接口（rest_command版）
trigger:
  - platform: state
    entity_id: sensor.xiaomi_l05b_af0a_conversation  # 小爱语音文字传感器ID（需替换为自己的）
condition:
  - condition: template
    value_template: "{{ trigger.to_state.state | trim != '' }}"  # 过滤空指令（避免无语音时触发）
action:
  # 1. 调用rest_command发送指令到API
  - service: rest_command.xiaoai_api_request
    data:
      text: "{{ trigger.to_state.state }}"  # 将小爱语音文字传递给API
  # 2. 延迟1秒，确保API执行完成，再播报提示
  - delay: "00:00:01"
  # 3. 小爱TTS播报“操作成功”，覆盖原生“没有设备”报错
  - service: xiaomi_miot.play_text
    data:
      entity_id: media_player.xiaomi_l05b_af0a  # 小爱音箱播放器实体ID（需替换为自己的）
      text: "操作成功"
mode: single  # 单次模式，避免重复触发
```

## 方案2：shell\_command 版自动化（推荐）

路径同上，粘贴以下YAML，适配稳定版配置：



```yaml
alias: 小爱语音转发到AI接口 

trigger:  

​	- platform: state    

​	entity_id: sensor.xiaomi_l05b_af0a_conversation 

condition:  

​	- condition: template    

​	value_template: "{{ trigger.to_state.state | trim != '' }}" 

action:  

​	- service: shell_command.send_ai_request    

​		data:     

​	 	text: "{{ trigger.to_state.state }}" mode: single
```



## 使用call action

```yaml
alias: 小爱语音转发到AI接口（shell_command推荐版）
trigger:
  - platform: state
    entity_id: sensor.xiaomi_l05b_af0a_conversation  # 你的小爱语音文字传感器ID
condition:
  - condition: template
    value_template: "{{ trigger.to_state.state | trim != '' }}"  # 过滤空指令
action:
  # 1. 调用shell_command发送curl请求到API（不超时）
  - service: shell_command.send_ai_request
    data:
      text: "{{ trigger.to_state.state }}"  # 传递小爱语音文字
  # 2. 延迟1秒，确保API执行完成
  - delay: "00:00:01"
  # 3. 替换为兼容的小爱TTS播报服务（解决未知动作问题）
  - service: xiaomi_miot.call_action
    data:
      entity_id: media_player.xiaomi_l05b_af0a  # 你的小爱音箱播放器实体ID
      action: play_text
      params:
        text: "操作成功"  # 可修改为自定义播报话术
mode: single
```

## 使用play_text

```yaml
alias: 小爱语音转发到AI接口（shell_command推荐版）
trigger:
  - platform: state
    entity_id: sensor.xiaomi_l05b_af0a_conversation  # 小爱语音文字传感器ID
condition:
  - condition: template
    value_template: "{{ trigger.to_state.state | trim != '' }}"  # 过滤空指令
action:
  # 1. 调用shell_command发送curl请求到API（不超时）
  - service: shell_command.send_ai_request
    data:
      text: "{{ trigger.to_state.state }}"  # 传递小爱语音文字
  # 2. 延迟1秒，确保API执行完成
  - delay: "00:00:01"
  # 3. 小爱TTS播报自定义提示，覆盖原生报错
  - service: xiaomi_miot.play_text
    data:
      entity_id: media_player.xiaomi_l05b_af0a  # 小爱音箱播放器实体ID
      text: "操作成功"  # 可修改为“打开成功”“已关闭”等
mode: single
```

# 六、关键实体ID查找方法

自动化中需要两个核心实体ID（必须正确，否则无法触发/播报），查找方法如下：

## 1\. 小爱语音文字传感器ID（trigger用）

用途：接收小爱音箱的语音转文字，对应自动化中的 `sensor\.xiaomi\_l05b\_af0a\_conversation`。

1. HA首页 → 右上角「设置」；

2. 进入「设备与服务」；

3. 找到「Xiaomi MIoT」集成，点击进入；

4. 在设备列表中找到你的小爱音箱（例：小爱音箱Play L05B）；

5. 点击设备进入详情页，往下翻找到「实体」列表；

6. 找到名称包含「conversation」的传感器，复制其完整ID（如 `sensor\.xiaomi\_l05b\_af0a\_conversation`）。

## 2\. 小爱音箱播放器ID（TTS播报用）

用途：调用小爱音箱播报自定义文字，对应自动化中的 `media\_player\.xiaomi\_l05b\_af0a`。

1. 方法同上，进入小爱音箱设备详情页的「实体」列表；

2. 找到前缀为 `media\_player\.` 的实体，复制其完整ID（如 `media\_player\.xiaomi\_l05b\_af0a`）；

3. 备用方法：HA左侧「开发者工具」→「实体」→ 搜索 `media\_player\.xiaomi`，快速找到对应实体。

# 七、常见问题及解决方案（实战踩坑汇总）

## 问题1：HA调用API超时（timeout）

- 现象：日志报 `Error fetching data: Cannot connect to host \.\.\. timeout`；

- 原因：rest\_command在Linux Docker \+ host网络下存在BUG，无法正常路由；

- 解决：改用 `shell\_command \+ curl`（推荐），或确认HA容器已启用 `\-\-net=host`。

## 问题2：host\.docker\.internal 无法解析（Domain name not found）

- 现象：日志报 `Cannot connect to host host\.docker\.internal:6002 ssl:default \[Domain name not found\]`；

- 原因：Linux系统不支持 `host\.docker\.internal` 这个域名（仅Windows/macOS Docker支持）；

- 解决：将URL替换为API的真实局域网IP（`192\.168\.1\.40:6002`）。

## 问题3：小爱播报“没有设备”

- 现象：小爱收到指令后，播报“没有设备”，但API已执行成功；

- 原因：小爱音箱本地尝试解析米家设备，找不到对应设备则播报报错；

- 解决：
        

    1. 米家APP → 找到对应小爱音箱 → 关闭「语音控制智能家居」「自动场景执行」；

    2. 在HA自动化中添加TTS播报，用“操作成功”覆盖原生报错（已在自动化中配置）。

## 问题4：YAML格式报错（expected a dictionary / 缩进错误）

- 现象：HA重启失败，日志报 `expected a dictionary\. Got \.\.\.`；

- 原因：
        

    1. 自动化代码错误粘贴到 `configuration\.yaml` 内；

    2. YAML缩进不对（需用空格缩进，不可用Tab）；

    3. 引号不匹配（如payload的引号混用）。

- 解决：
        

    1. 自动化必须在「自动化编辑器」中粘贴，不可写在 `configuration\.yaml`；

    2. 复制文档中提供的YAML，确保缩进一致（推荐4个空格缩进）；

    3. 检查引号：rest\_command的payload用单引号包裹，内部JSON用双引号。

## 问题5：shell\_command 调用失败（curl: command not found）

- 现象：日志报 `curl: command not found`；

- 原因：HA容器内未安装curl；

- 解决：执行命令安装curl：`docker exec \-it homeassistant apk add curl`。

## 问题6：Xiaomi MIoT 集成警告（entity ID wrong domain）

- 现象：日志报 `Detected that custom integration \&\#39;xiaomi\_miot\&\#39; sets an entity ID with wrong domain`；

- 原因：Xiaomi MIoT集成的实体域名不规范（不影响使用）；

- 解决：无需处理，不影响功能；若想根治，可前往 [Xiaomi MIoT GitHub](https://github.com/al-one/hass-xiaomi-miot/issues) 提交BUG反馈。

# 八、测试方法（从底层到上层，排错必备）

测试顺序：先测API → 再测容器内访问 → 最后测自动化，确保每一步都正常。

## 1\. 测试API是否可访问（宿主机测试）

在HA宿主机（192\.168\.1\.51）的终端执行，验证API本身是否正常：

```bash
curl -X POST http://192.168.1.40:6002/api/ai-advanced -H "Content-Type: application/json" -d '{"text":"关闭扫地机"}'
```

✅ 成功：返回JSON格式的成功信息（如 `\{\&\#34;code\&\#34;:200,\&\#34;msg\&\#34;:\&\#34;AI高级解析完成\&\#34;\}`）；

❌ 失败：检查API是否启动、6002端口是否开放、IP是否正确。

## 2\. 测试HA容器内访问（关键测试）

模拟HA内部调用API，验证容器网络是否正常：

```bash
docker exec -it homeassistant curl -X POST http://192.168.1.40:6002/api/ai-advanced -H "Content-Type: application/json" -d '{"text":"关闭扫地机"}'
```

✅ 成功：返回与宿主机测试相同的JSON；

❌ 失败：检查HA容器是否启用 `\-\-net=host`，重启容器重试。

## 3\. 测试自动化触发（最终测试）

1. 对小爱音箱说：“打开扫地机”；

2. 查看HA活动记录：HA → 左侧「活动」，确认自动化已触发；

3. 查看API日志：确认API收到指令并执行；

4. 查看小爱音箱：是否播报“操作成功”；

5. 查看设备：确认扫地机已执行对应操作（打开/关闭）。

# 九、日志查看方法（排错核心）

## 1\. 查看HA完整日志

1. HA首页 → 右上角「设置」；

2. 进入「系统」→「日志」；

3. 点击「加载完整日志」，可查看所有HA运行日志。

## 2\. 关键日志搜索关键词（快速定位问题）

- rest\_command：排查rest\_command相关错误；

- shell\_command：排查shell\_command相关错误；

- automation：排查自动化触发、执行错误；

- xiaomi\_miot：排查小爱音箱集成相关错误；

- timeout：排查网络超时问题；

- error：查看所有错误日志。

## 3\. 成功日志特征（确认系统正常运行）

- 无timeout、client\_error等错误；

- 自动化日志：`Automation triggered by state change of sensor\.xiaomi\_l05b\_af0a\_conversation`；

- shell\_command/rest\_command日志：无错误提示，或显示「Successfully called」；

- API日志：收到请求并返回200成功。

# 十、最终效果（已实现）

- ✅ 对小爱说话，语音文字可正常同步到HA；

- ✅ HA自动化正常触发，成功调用API；

- ✅ API正常执行设备控制；

- ✅ 小爱音箱播报“操作成功”，不再报“没有设备”；

- ✅ 全程无超时、无报错，系统稳定运行。

# 十一、补充说明

- 文档中所有IP、实体ID均为示例，需替换为自己的实际信息；

- 推荐长期使用 `shell\_command` 方案，避免Docker环境下的超时问题；

- 若需修改播报话术，直接修改自动化中 `text: \&\#34;操作成功\&\#34;` 即可（如“打开成功”“已关闭扫地机”）；

- 若API地址、端口变更，需同步修改 `configuration\.yaml` 中的URL。

> （注：文档部分内容可能由 AI 生成）
