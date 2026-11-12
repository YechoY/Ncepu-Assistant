# 慧生活798 登录接口签名（2026-11 协议变更）

> 记录 `请升级最新版应用`（code=-1）的真实原因、正确的登录协议，以及盐值失效后的重新获取方法。
> 适用于 `packages/huish` 模块，供后续维护者参考。

## 1. 现象

登录时（手机号 + 图形验证码 + 短信验证码全部正确）返回：

```json
{"code":-1,"msg":"请升级最新版应用"}
```

但短信能正常收到，`/api/v1/acc/login/code` 返回 `{"code":0}`。

## 2. 排错过程中被否定的假设

| 假设 | 验证方式 | 结论 |
| --- | --- | --- |
| 版本号过旧 | 分别用 `VersionCode: 8.2.9` / `31010` / `3.1.10`（UA 同步改写） | 三种全部返回同一句"请升级"，与版本无关 |
| 缺 `openCode` / `cid` | 补空值提交 | 服务端完全无视，仍返回验证码相关错误 |
| 缺 `s`（图形验证码会话） | 带/不带 `s` 提交 | 无影响 |
| cookie 会话丢失 | 抓 `set-cookie` | 登录链路并未下发 cookie |
| IP 差异 | — | 与 IP 无关 |

关键判据：**验证码已经被消耗**，说明凭证校验是通过的，"请升级"发生在凭证校验之后。

## 3. 真实原因

`请升级最新版应用` 是一句**伪装文案**——服务端对 `/api/v1/acc/login` 增加了客户端签名校验，**请求缺少 `sign` 参数时返回这句话**。

进一步验证：带上一个错误格式的 `sign` 时，返回会变成 `验签失败`，说明：

- 缺 `sign` → `请升级最新版应用`
- 有 `sign` 但校验不过 → `验签失败`
- `sign` 正确 → `code: 0` + token

## 4. 正确协议

```http
POST https://i.ilife798.com/api/v1/acc/login?sign=<sign>
Content-Type: application/json
ApplicationType: 1,1
VersionCode: 3.1.9
user-agent: Android_ilife798_3.1.9
Accept-Language: zh-Hans-CN;q=1

{"un":"<手机号>","authCode":"<短信验证码>"}
```

签名算法：

```
sign = md5("authCode=" + 短信验证码 + "&un=" + 手机号 + SIGN_SALT)
```

- 盐值放在**最后**直接拼接，不加分隔符
- 结果是小写 32 位十六进制
- `sign` 放在 **URL 查询串**，不是请求体

当前有效盐值：

```
AbCdEfGhIjKlMnOpQrStUvWxYz12345
```

### 注意：版本头

`ApplicationType` / `VersionCode` / `user-agent` 三者是一组**协议标识**，和官方 App 自己的 `versionName`（如 3.1.10）无关：

- 设备控制通道：`ApplicationType: 1,1` + `VersionCode: 3.1.9` + `user-agent: Android_ilife798_3.1.9`
- 账户服务通道：`ApplicationType: 1,5` + `VersionCode: 2.0.83`（该通道不验签，但需要 `cid`）

`user-agent` 必须写成 `Android_ilife798_<与 VersionCode 相同的值>`，不能只改其中一个。

## 5. 哪些接口需要签名

| 接口 | 是否需要 `sign` |
| --- | --- |
| `POST /api/v1/acc/login` | 需要（本文档主题） |
| `GET /api/v1/acc/stat` | 需要 |
| `GET /api/v1/dev/start`、`/dev/stop` | 不需要，仅靠 `Authorization` |
| `POST /api/v1/acc/login/code` | 不需要 |
| `GET /api/v1/ui/app/master`、`/ui/app/dev/*` | 不需要 |

`/dev/*` 与 `/acc/stat` 之外的业务接口只校验 `Authorization`。

> 设备控制类接口的签名格式（若日后被加入校验）为：
> `md5(adId + 30*(服务器时间毫秒/30000) + token 后 8 位 + uid 后 8 位 + APP_SIGN_SALT)`，
> 时间桶为 30 秒，需要先用响应头 `Date` 校准服务器时间。

## 6. 代码实现

`packages/huish/lib/src/huish_api_client.dart`：

- `_signSalt`：盐值常量
- `_loginSign(phone, smsCode)`：生成签名
- `login()`：把 `sign` 拼到查询串，body 只发 `{un, authCode}`
- `_post(..., query: {...})`：支持查询串参数

## 7. 盐值失效后如何重新获取

盐值会随官方客户端更新而更换。官方 App 被爱加密加固，直接反编译拿不到，但**开源实现会把它编译进 APK**：

1. 从 [nocookies111/life-798 Releases](https://github.com/nocookies111/life-798/releases) 下载最新 Release APK；
2. 解包取 `classes.dex`；
3. 反汇编后搜索 `const-string` 中的 `"authCode="`：

```powershell
$dd = 'D:\Android\Sdk\build-tools\35.0.0\dexdump.exe'
& $dd -d classes.dex | Select-String -Pattern 'const-string.*"authCode="' -Context 0,12
```

4. 紧跟在 `"authCode="`、`"&un="` 之后的那个 `const-string` 就是盐值（编译期常量被内联在调用处）。

也可以直接对 dex 做字符串提取，找 32 位左右的随机串交叉验证。

## 8. 验证记录

2026-11-12 实测：

```
sign = md5("authCode=123456&un=13800138000AbCdEfGhIjKlMnOpQrStUvWxYz12345")
     = c680c9431948f79c8a3253a100b03944

POST /api/v1/acc/login?sign=c680c9431948f79c8a3253a100b03944
→ {"code":0,"data":{"al":{"token":"...","uid":"...","eid":"..."}}}
```

（示例中的手机号与验证码为占位值，仅用于演示签名计算，勿使用真实凭证。）

## 9. 排错经验

- 服务端文案不可信。`请升级最新版应用` 的实际含义是"缺少客户端签名"。
- 用**错误响应差异**做探针：改变一个参数后错误码/文案变化，说明这个参数被服务端读取（例如 `sign` 从缺失变成错误格式，文案从"请升级"变成"验签失败"）。
- 不要靠猜签名算法烧验证码。短信验证码一次性，改一次参数就要重新走完整登录流程，成本高；应优先从公开实现 / Release 包中拿到确定值。
