$Prompt = @"
读取 AGENTS.md 和 STATE.md：

默认允许以下命令自动执行，不需要再次确认：
- flutter test
- flutter analyze
- dart test
- dart format

1. 理解当前项目状态
2. 从 STATE.md 的【下一步】开始继续开发
3. 不重复已完成内容
4. 如果本轮有新进展，结束前更新 STATE.md
5. 保持 STATE.md 简洁，只记录对下次有用的内容
"@

codex $Prompt