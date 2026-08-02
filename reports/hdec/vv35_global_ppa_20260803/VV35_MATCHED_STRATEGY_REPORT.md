# VV35 匹配综合策略报告

所有策略均使用冻结的同一4694候选RTL。每次运行前后文件哈希保持一致，并与主VV35候选的规范化内容一致。

| 策略 | Logic LUT | FF | WNS | 相对Default | 结论 |
|---|---:|---:|---:|---|---|
| Default | 4694 | 1513 | 0.293 ns | 基线 | 保留 |
| `flatten_hierarchy=full` | 4666 | 1514 | 0.272 ns | -28 LUT，+1 FF，-0.021 ns | 拒绝 |
| `resource_sharing=on` | 4670 | 1514 | 0.272 ns | -24 LUT，+1 FF，-0.021 ns | 拒绝 |
| full加sharing | 4666 | 1514 | 0.272 ns | -28 LUT，+1 FF，-0.021 ns | 拒绝 |

三个面积导向候选均违反“Logic LUT与FF均不得增加”以及WNS不低于0.280 ns的门槛。最终结果保留Default策略，不能把4666 LUT作为可提交VV35数字。
