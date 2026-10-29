# rules-next

自用的 Mihomo 分流规则：每天自动从上游同步一次，配置里引用这个仓库的地址，上游改名、换分支或删库也不影响使用。

## 在 Mihomo 里引用

```yaml
c: &c {type: http, behavior: classical, format: text, interval: 86400}

rule-providers:
  Direct: {<<: *c, url: https://github.com/1432433gg/rules-next/raw/main/rules/Direct.list}
  Netflix: {<<: *c, url: https://github.com/1432433gg/rules-next/raw/main/rules/Netflix.list}
```

地址格式：`https://github.com/1432433gg/rules-next/raw/main/rules/名称.list`

也可以用 jsDelivr：`https://fastly.jsdelivr.net/gh/1432433gg/rules-next@main/rules/名称.list`。jsDelivr 有缓存，同步后通常几小时内更新。

## 自己加规则

在 `custom/` 里放 `名称.list`，一行一条规则（`DOMAIN-SUFFIX,example.com` 这种格式）：

- 名称和 `rules/` 里已有的一样（比如 `Proxy.list`），就追加到那个规则后面；
- 名称是新的，就单独生成一个 `rules/名称.list`，配置里再加一个 rule-provider 引用它。

不要直接改 `rules/` 里的文件，下次同步会被覆盖。

## 增减同步的规则

改 `sources.txt`：一行一个，`名称  上游地址`。加一行就多同步一个，删一行下次同步时文件也会删掉。

## 目录

```
rules/                         生成的规则文件（自动同步，不要手动改）
custom/                        自己补充的规则
sources.txt                    要同步的规则和上游地址
scripts/update.sh              下载、检查、合并规则
.github/workflows/update.yml   每天自动同步
LICENSE-Repcz                  Repcz/Tool 的 MIT 许可证
```

## 致谢

- [Repcz/Tool](https://github.com/Repcz/Tool)（MIT，见 [LICENSE-Repcz](LICENSE-Repcz)）
