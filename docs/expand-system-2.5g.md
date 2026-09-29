# Archimedes 64G 扩容到 2.5 GiB：极简教程

仅适用于 Archimedes / MT6761 / 64G eMMC。脚本必须在 TWRP 的 root `adb shell`
中运行，不接受参数，也不会自动刷镜像。

## 风险

这是破坏性操作：`userdata` 会被清除，`system/vbmeta/cache` 的原有内容也会被
重建；中断、断电、型号或容量不符都可能损坏 GPT、变砖。务必保留 scatter 和
救砖工具。只有脚本提示时输入小写 `y` 才会继续。

## 操作

```powershell
adb reboot recovery
adb push tools/expand_system_archimedes_64g_2.5g.sh /tmp/expand-system-2.5g.sh
adb shell
```

在 TWRP shell 中先确保 System、Vendor、Product、Data、Cache、`/sdcard` 均未挂载，
然后执行：

```sh
sh /tmp/expand-system-2.5g.sh
y
```

脚本显示 `DONE` 后：

```sh
reboot recovery
```

重新进入 TWRP 后执行 **Format Data**，再用 TWRP 的 **Install Image** 刷入对应的
`system.img`、`vendor.img`、`vbmeta.img`（以及同一套包中的 dtbo/lk/lk2，若设备包
要求）。最后重启系统。

脚本固定目标为 2.5 GiB，只检查 Archimedes 64G 的已知 GPT 边界；不匹配会拒绝执行。
