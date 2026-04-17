# WaypointUI Gamepad

为 [WaypointUI](https://github.com/kaytotes/WaypointUI) 弹窗添加手柄操作支持的 WoW 插件。

Add gamepad support to WaypointUI prompt dialogs for World of Warcraft.

## 功能

- D-Pad / 左摇杆切换按钮焦点
- 手柄确认/取消键操作（兼容 Switch Pro Controller 布局）
- ConsolePort 提示栏集成
- Prompt 缩放（1.5x），在掌机/Steam Deck 上更易操作
- 战斗状态自适应（进出战斗自动处理输入注册）

## 依赖

- **WaypointUI**（必需）
- **ConsolePort**（可选，用于提示栏集成）

## 安装

将 `WaypointUI_Gamepad` 文件夹放入：

```
World of Warcraft/_retail_/Interface/AddOns/
```

## 配置

运行时调整 Prompt 缩放比例：

```lua
/run WaypointUI_Gamepad.SetPromptScale(1.3)  -- 设为 1.3 倍
/run WaypointUI_Gamepad.GetPromptScale()      -- 查看当前缩放
```

## License

MIT
