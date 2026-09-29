# Wi-Fi worklog — 2026-09-29

## Root cause captured

The stable vendor module (`2644b85eeddbae5c9b2c667a6bb937329697d5f6ab9517360b61bdf249d6024c`) reproduced the failure under concurrent upload/download. The kernel log shows repeated EMI MPU violations from `MT6761_M7_AXI_MST_CONNSYS_WIFI_PDMA`, followed by malformed RX packet types, `nicProcessIST` failure, and TX token exhaustion (`Used:512/512`). The apparent link drop is a downstream HIF/token deadlock, not a gateway-only disconnect.

## Fix baseline

The external Gen4M source was cleaned of generated objects and rebuilt from an independent kernel output. Commit `122abfa` changes the MT6761 preallocated AXI path, keeps the reserved Wi-Fi window explicit, uses the 32-bit DMA mask, and adds the 4.9 compatibility stubs. Its required WMT symbols are resolved from the vendor `Module.symvers`; no stale object files are reused.

Patch: `vendor/archimedes-wlan/0001-mt6761-prealloc-axi-dma.patch`

The clean module was built with 24 jobs on the Linux sandbox (32 CPUs, 82 GiB RAM, 36 GiB free disk), has vermagic `4.9.117-agui@caner`, and SHA-256 `05f992f874d219b0d5ff2546f27097303e11e8b7416324e657275e59b85e9a3c`.

## Test and rollback

Before testing, the stable module was pulled back to the local artifacts directory. The Android `/vendor` copy was transient, so the candidate was written through TWRP to the actual vendor partition. At the time of recording, the device had not yet reappeared on ADB after the reboot; do not treat the candidate as validated until boot and stress logs are captured.
