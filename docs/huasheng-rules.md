# 华盛通分流核验记录

核验日期：2026-10-31（Asia/Shanghai）。本次仅修改本地副本，未推送 GitHub。

## 结论

原 Broker 规则只有 hstong.com、vbkr.com、vbkrhk.com、valuable.com.hk 四个主域，确实遗漏 hstbroker.com。新增规则不附带 :443：DOMAIN-SUFFIX,hstbroker.com 同时覆盖 web-api.hstbroker.com 及其其他子域和端口。

华盛通部分现在共 24 条：22 条域名后缀、1 条第三方专属主机、1 条官方备用 IPv4 /32；相比原规则增加 20 条。保持 Broker 策略组，不强制改成 DIRECT 或指定代理。

## 证据及范围

1. 从 [华盛官网](https://www.vbkr.com/) 的下载链接取得官方 Android 2.9.710 安装包；只静态读取 ZIP 中的配置，不安装或登录。
2. APK URL：https://r.vbkr.com/public/app/Android/HSTONG_100000_2.9.710_1793327197.apk
3. APK SHA-256：c3cdb03bfd73a0e85710e1537609a0a4bf20d40934360bf760403608bfe96ea9
4. [在线备用域名池](https://assets.hstong.com/app/conf/host-pool.json) 和 [在线备用 IP 池](https://r.hstong.com/v2/commons/app/hs_ip_address_pool_release.json) 均取得 HTTP 200 JSON。备用 IP 为 150.109.153.202，仅增加 /32。
5. https://web-api.hstbroker.com/ 实际取得 HTTP 200，响应包含 system=hs-web-api、华盛证券web。没有提交登录、交易或账户请求。
6. 官网页面及资源：hstong.com/about、vbkr.com、vbkrhk.com、vbkhk.com、vclbrokers.com、valuable.com.hk；vclbroker.com/beian/ 自述深圳价值网络科技有限公司隶属华盛资本集团。
7. 社区搜索用作发现候选：[Aethersailor 规则](https://github.com/Aethersailor/Custom_OpenClash_Rules/blob/main/rule/Custom_Direct.list)。最终主要依据官方 APK 和在线配置，而非把社区规则直接复制。

内置网页搜索接口本次返回错误；改用 GitHub 在线代码搜索、公开网页搜索及直接 HTTPS 获取官方页面、资源和安装包。Bing 检索质量不足，Google 返回访问验证页，均未作为结论证据。

### 官方应用配置中的 15 个主域

来源：assets/HSAPPCONFIG → data.config.commons.WEBVIEW_COOKIE_DOMAINS，包含业务、分享、Cookie 兼容及备用域名，不意味着每个主域都有可浏览的首页。

```text
hstong.com
valuable.com.hk
vbkr.com
vbkrhk.com
vbkhk.com
vtradetech.com
valuablebrokers.com
vcltrade.com
vclbroker.com
vclbrokers.com
hstbroker.com
aul711.com
tradingdesk.vip
tradingdesk.info
vil-vbkr.com
```

### 客户端域名名单中另外 7 个主域

来源：res/GaZ.json 的 domainName 项。部分亦用于客服或内部环境；这里确认的是官方客户端包含这些域名，不声称全部域名当前有交易流量或对外提供网页。

```text
vbkr.com.cn
hszq8.com
hszq.com.cn
hszq8.cn
hszq6.com
vbkr.cn
25000388.com
```

### 专属第三方主机和备用 IP

- `DOMAIN,valuable-zz.zszzcloud.com`：官方配置 Thirdsimulatedstockpage 指向该模拟交易主机，只加入完整主机，不加入 zszzcloud.com 整个云平台。
- `IP-CIDR,150.109.153.202/32,no-resolve`：官方实时备用池明确提供。IP 归属和用途可能变化，应随官方地址池复核，不扩展为 /24 等网段。

### 明确排除

- `aud711.com`：官网 JS 中可见该字符串，但官方当前 APK 与在线备用池均使用 `aul711.com`；本次不把 aud711.com 猜作有效备用域名。
- `com.hstong.net`、`com.hstong.app`：APK 中的包名/类名文本，不能直接当作网络域名。
- 腾讯、百度、Google、Facebook 等共享统计、验证码、DNS 和 CDN 主域：不因为网页引用就把整个平台分给 Broker。
- 未把社区提供的其他云服务器 IP 或网段照搬进来。

## 验证结果

- 使用真实 Mihomo v1.19.33，读取本次 Broker.list，配置检查通过。
- 27 项实际内核分流检查全部通过：24 个正例命中 Broker、3 个相似域名/共享云平台反例未命中。正例包括 web-api.hstbroker.com。
- 内核测试将目标域名映射到本地测试 HTTP 服务，以 Broker→DIRECT、兜底→REJECT 判断匹配；这是规则匹配验证，不是各域名的公网连通性测试。
- 73 个官方应用配置及在线备用池主机均被覆盖；5 个静态反例不误匹配。
- 检查模板中先于 Broker 的 NetflixBlock、Lan、Direct、Reject、AI 域名规则，没有发现上述主机抢先匹配；备用 IP 亦未与这些规则的 IPv4 CIDR 冲突。该检查不代表用户自行修改的运行配置。
- 运行项目原有 scripts/update.sh，限定 Broker 输入，在临时目录生成 Mihomo 和 Quantumult X 格式，与本地两个输出文件逐字节一致。
- git diff --check 通过。

## 验证边界

没有登录华盛通账户，没有做下单、入金、提款或完整 App 抓包测试。部分域名首页返回空白、403，部分请求从当前出口返回 503，不能把这些响应解释为业务域名不存在，也不能宣称这些域名公网可用。不同版本、地区和账户的动态下发域名仍可能不同，因此本结果是“当前公开官方配置可确认的覆盖”，不是永不遗漏的完整域名保证。

修改文件：custom/Broker.list（持久来源）、rules/Broker.list（Mihomo）、quantumultx/rules/Broker.list（Quantumult X）。新增项沿用现有 Broker 分组选择。
