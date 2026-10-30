# 券商规则后续核验（2026-10-31，Asia/Shanghai）

本次接续第二批提交 `be221c7`，补充 11 条：富途/Moomoo 8 条、嘉信 3 条。Broker 总规则从 188 条增至 199 条；三个规则文件同步，策略组和其他分流顺序不变。

## 本次补充及证据

| 规则 | 官方证据与验证范围 |
| --- | --- |
| `DOMAIN-SUFFIX,futuhk1.com` | [来源](https://static.futunn.com/futuhk_common/dist/futuhkHeadFoot-01e221a90427e83400b5.js)：官方头尾脚本的开户、入金、出金、账户与 passport URL 兼容正则明确包含该根域；证明软件配置支持，不证明所有主机当前可达。 |
| `DOMAIN-SUFFIX,futuhongkong.com` | [来源](https://static.futunn.com/futuhk_common/dist/futuhkHeadFoot-01e221a90427e83400b5.js)：官方头尾脚本的开户、入金、出金、账户与 passport URL 兼容正则明确包含该根域；证明软件配置支持，不证明所有主机当前可达。 |
| `DOMAIN-SUFFIX,futunh.com` | [来源](https://static.futunn.com/futuhk_common/dist/futuhkHeadFoot-01e221a90427e83400b5.js)：官方头尾脚本的开户、入金、出金、账户与 passport URL 兼容正则明确包含该根域；证明软件配置支持，不证明所有主机当前可达。 |
| `DOMAIN-SUFFIX,futuhk8.com` | [来源](https://static.futunn.com/futuhk_common/dist/futuhkHeadFoot-01e221a90427e83400b5.js)：官方头尾脚本的开户、入金、出金、账户与 passport URL 兼容正则明确包含该根域；证明软件配置支持，不证明所有主机当前可达。 |
| `DOMAIN-SUFFIX,futusg.com` | [来源](https://static.futunn.com/official_global_website/futuhk/assets/main-dde45950.js)：官方脚本 Moomoo 平台支持域 FA 包含 futusg.com；本轮 HTTPS 请求跳转到 www.moomoo.com/403。 |
| `DOMAIN,passport.moomooapp.com` | [来源](https://static.futunn.com/official_global_website/futuhk/assets/main-dde45950.js)：官方脚本 TP 登录主机数组明确列出该主机；只添加精确主机，不推定整个根域所有业务用途。 |
| `DOMAIN,passport.moomoocn.com` | [来源](https://static.futunn.com/official_global_website/futuhk/assets/main-dde45950.js)：官方脚本 TP 登录主机数组明确列出该主机；只添加精确主机，不推定整个根域所有业务用途。 |
| `DOMAIN,passport.moomoobull.com` | [来源](https://static.futunn.com/official_global_website/futuhk/assets/main-dde45950.js)：官方脚本 TP 登录主机数组明确列出该主机；只添加精确主机，不推定整个根域所有业务用途。 |
| `DOMAIN-SUFFIX,thinkorswim.com` | [来源](https://www.schwab.com/trading/thinkorswim)：官方产品页的 Log in now 链接指向 https://trade.thinkorswim.com。目标本轮访问超时，不声明可登录。 |
| `DOMAIN-SUFFIX,schwabcdn.com` | [来源](https://client.schwab.com/Areas/Access/Login)：官方登录页 preload 的 CharlesModern 字体从 client.schwabcdn.com/Areas/Access/Content/login/dist/font/ 加载。 |
| `DOMAIN-SUFFIX,schwabassetmanagement.com` | [来源](https://www.schwabfunds.com/)：已在嘉信官网引用的 schwabfunds.com 跳转至 www.schwabassetmanagement.com；重定向请求最终超时，但独立请求目标站 HTTP 200、标题 Schwab Asset Management | Home，页脚链接 schwab.com。 |

富途两个 JS 文件均来自 `static.futunn.com`，已实际下载（HTTP 200），并静态检查相关域名数组和业务 URL 正则；未执行网页挑战脚本。`futuhk1.com` 官网页面也成功返回，canonical 指向 `www.futuhk.com`。文件 SHA-256、响应状态和访问失败情况保存在 [证据记录](broker-followup-evidence-2026-10-31.json)。

`passport.moomoobull.com` 不在原 `DOMAIN-SUFFIX,api.moomoobull.com` 覆盖范围中；本次补精确主机。Moomoo 另外两个备用登录域也只补 passport 主机，不因官网跳转扩大到整个父域。

## 实际验证

- 第二批的 188 条规则已补做 56 项真实 Mihomo 分流检查，全部通过。
- 本次 199 条规则用 **Mihomo v1.19.33** 重新执行配置检查和 **97 项分流检查（68 正例、29 反例）**，全部通过。
- 正例包括华盛通、第二批和本批新增主机/根域；反例包括伪装后缀、相似根域和精确主机的子域。逐项结果见 [结果 JSON](broker-core-results-2026-10-31.json)。
- 测试只把目标主机映射到本地 HTTP 服务，由真实 Mihomo 加载本地 Broker provider；Broker 走 DIRECT，兜底 REJECT。验证真实内核的规则解析与匹配，不证明外部服务连通、真实账户登录或交易成功，也没有逐一验证既有 IP 网段。
- 使用仓库原有 `scripts/update.sh` 分别生成 Mihomo、Quantumult X 文件，并对规则条数、重复项、转换结果和正反例进行核对。Quantumult X 没有执行客户端运行测试。
- 对 `be221c7` 中 Broker 之前的 NetflixBlock、Lan、Direct、Reject、AI 域名规则进行检查，68 个正例没有提前命中。Direct 的 `DST-PORT,22` 不影响 HTTPS 443；没有对真实 DNS 解析后的所有 IP 作断言。

复测脚本会等待控制接口报告 Broker 已加载 199 条规则，再发测试请求，避免端口先监听、provider 尚未就绪造成误判。

复测命令（在仓库目录执行；输出目录用于测试文件，不要指向实际运行配置目录）：

```bash
python3 tests/verify_broker_rules.py --mihomo /path/to/mihomo --output /path/to/test-output
```

## 仍未加入的候选

- `ftesop.com`：本轮 HTTP 439；已检查的官方资源未提供足够用途证据，第三方客户端分析笔记不能替代本次独立核验。
- `itigergrowth.com`：官网 `SiteLinker` / `linkerDomains` 统计配置确实列出；根站 HTTP 503。目前只确认跨域统计配置关系，未获得实际业务或资源引用证据，暂不加。带 a 的 `itigergrowtha.com` 已在第二批加入且有实际 script src 引用。
- `skytigris.cn`：HTTP 200，标题 Tiger Fintech，引用 `static.tigerfintech.com` 和 `c1.itigergrowtha.com`；目前缺少从已确认老虎官网指向该站或具体客户端用途的进一步证据，保留候选状态。注意老虎统计配置中的 `skytigris.com` 是另一个域名。
- 老虎统计配置还包含其他地区/历史候选，运行配置也包含 UAT 测试环境；没有仅按字符串批量加入。共享云、广告平台、社交站点及新增 IP 网段均未扩展。

以上完成了本轮可验证候选的处理；待确认项明确保留。规则匹配测试不能证明覆盖所有地区、客户端版本、动态下发节点及账户业务。
