# 券商规则补充核验（2026-10-31）

## 已补充

在华盛通补充提交 0c4c6bd 之后，增加 13 条规则：老虎 4 条、长桥 1 条、嘉信 8 条。保持现有 Broker 策略组，并同步 custom/Broker.list、rules/Broker.list 和 quantumultx/rules/Broker.list。

| 券商 | 规则 | 官方依据 |
| --- | --- | --- |
| Tiger | `DOMAIN-SUFFIX,itigergrowtha.com` | [来源](https://www.itiger.com/sg/)：官网 script src 引用 https://c1.itigergrowtha.com/portal5/static/js/runtime.3204b96f.js 等资源 |
| Tiger | `DOMAIN-SUFFIX,tigerbrokers.com.sg` | [来源](https://www.itiger.com/sg/)：官网链接 www.tigerbrokers.com.sg 与 developer.tigerbrokers.com.sg |
| Tiger | `DOMAIN-SUFFIX,tigertrade.app` | [来源](https://www.itiger.com/sg/)：官网链接 www.tigertrade.app |
| Tiger | `DOMAIN,sg.tigerkickoff.com` | [来源](https://www.itiger.com/sg/)：官网运行配置列出 sg.tigerkickoff.com；仅加入观察到的精确主机 |
| Longbridge | `DOMAIN-SUFFIX,longbridge.cn` | [来源](https://github.com/longbridge/longbridge-terminal/blob/c23b9056670c99ee3c7869bf7aa16813346fa151/src/update.rs)：官方终端代码使用 https://open.longbridge.cn/docs/cli/release-notes.md，原规则只有三个 openapi 精确域名，未覆盖 open.longbridge.cn |
| Schwab | `DOMAIN-SUFFIX,aboutschwab.com` | [来源](https://www.schwab.com/)：嘉信官网 HTML 明确链接或引用该站点（本轮实际获取 HTTP 200） |
| Schwab | `DOMAIN-SUFFIX,schwab.com.sg` | [来源](https://www.schwab.com/)：嘉信官网 HTML 明确链接或引用该站点（本轮实际获取 HTTP 200） |
| Schwab | `DOMAIN-SUFFIX,schwabinstitutional.com` | [来源](https://www.schwab.com/)：嘉信官网 HTML 明确链接或引用该站点（本轮实际获取 HTTP 200） |
| Schwab | `DOMAIN-SUFFIX,schwab529plan.com` | [来源](https://www.schwab.com/)：嘉信官网 HTML 明确链接或引用该站点（本轮实际获取 HTTP 200） |
| Schwab | `DOMAIN-SUFFIX,schwabfunds.com` | [来源](https://www.schwab.com/)：嘉信官网 HTML 明确链接或引用该站点（本轮实际获取 HTTP 200） |
| Schwab | `DOMAIN-SUFFIX,csimfunds.com` | [来源](https://www.schwab.com/)：嘉信官网 HTML 明确链接或引用该站点（本轮实际获取 HTTP 200） |
| Schwab | `DOMAIN-SUFFIX,schwabplan.com` | [来源](https://www.schwab.com/)：嘉信官网 HTML 明确链接或引用该站点（本轮实际获取 HTTP 200） |
| Schwab | `DOMAIN-SUFFIX,schwabworkplaceservices.com` | [来源](https://www.schwab.com/)：嘉信官网 HTML 明确链接或引用该站点（本轮实际获取 HTTP 200） |

官网来源为本轮实际成功获取的 https://www.itiger.com/sg/ 和 https://www.schwab.com/ 的 HTML 引用。记录的是资源/链接关系，不表示已完成这些站点的登录或交易测试。

长桥原有三个 openapi.*.longbridge.cn 精确规则能覆盖对应 API，但无法覆盖官方终端使用的 open.longbridge.cn 文档入口；补充根域后缀解决该缺口。保留原精确规则以避免无关整理。

## 核验

- 53 个去重的域名匹配正反例检查通过；新增主机在旧 Broker 中均未命中，在新 Mihomo 和 Quantumult X 规则中均命中。
- 相似域名（如 fakeitigergrowtha.com、longbridge.cn.example.org）不误匹配；sg.tigerkickoff.com 只加精确主机，不包含整个父域。
- 当前 GitHub 上排在 Broker 前的 Lan、Direct、Reject、AI、NetflixBlock 域名规则未抢先匹配本次正例。未对这些域名解析后的所有 IP 做优先级断言。
- custom 与 Mihomo 输出一致；Quantumult X 按项目转换约定生成并核对，未重复添加规则。
- 规则总数从 175 增至 188。
- 后续已补做真实 Mihomo v1.19.33 测试：188 条规则版本的 56 项正反例全部通过；本次再补 11 条后，199 条规则版本的 97 项检查也全部通过。详情见 [后续核验](broker-followup-2026-10-31.md) 和 [逐项结果](broker-core-results-2026-10-31.json)。测试使用本地 HTTP 服务验证 Broker 匹配，不代表实际券商登录或交易成功。

## 第二批提交时的核验状态

以下候选状态为第二批提交时的记录；富途和嘉信部分候选已在后续完成核验并补充，最新结论见 [后续核验](broker-followup-2026-10-31.md)。

- 老虎官方 Python SDK 的 openapi.tigerfintech.com、openapi.tradeup.com、openapi-sandbox.tigerfintech.com，以及 cg.play-analytics.com 已由原规则覆盖。依据：https://github.com/tigerfintech/openapi-python-sdk/blob/e30d794489d09ce899536333d278d5356883dc13/tigeropen/tiger_open_config.py
- 长桥官方 SDK 的 openapi.longportapp.com 已由 longportapp.com 后缀覆盖。依据：https://github.com/longportapp/openapi/blob/72e9be585d2724358ddaf7d6afbb64bb9e01205d/rust/README.md
- 富途/Moomoo 官网请求进入 /403 页面；社区列出的 futuhk1.com、futuhongkong.com、futusg.com、moomooapp.com、moomoocn.com、ftesop.com 等候选尚未取得足够的一手归属/用途证据，本批不加入。这不代表富途没有遗漏。
- 社区列出的 itigergrowth.com、skytigris.cn、schwabcdn.com、thinkorswim.com、schwabassetmanagement.com 等也未在本轮完成独立的一手核验，因此暂不照抄。
- 官网引用的共享广告、社交平台、通用云域名和监管机构域名不加入券商规则；本次不增加任何云服务器 IP 网段。

## 边界

本补充针对公开页面、官方 SDK/终端及现有规则的可确认缺口，不保证覆盖所有客户端、地区和账户的动态下发域名。未执行登录、下单、入金、提款操作。仍需有实际设备连接日志或客户端配置，才能继续核验待确认候选。
