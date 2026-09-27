/* CM3232 ambient light backend for the MediaTek ALSPS framework. */
#define pr_fmt(fmt) "<CM3232> " fmt
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/slab.h>
#include "cust_alsps.h"
#include "alsps.h"

#define CM3232_DEV_NAME "CM3232"
#define CM3232_REG_CMD 0x00
#define CM3232_REG_ALS 0x50
#define CM3232_REG_ID 0x53
#define CM3232_CMD_DISABLE BIT(0)
#define CM3232_CMD_RESET BIT(6)
#define CM3232_CMD_DEFAULT 0x04
#define CM3232_HW_ID 0x32

struct cm3232_priv {
	struct alsps_hw hw;
	struct i2c_client *client;
	struct mutex lock;
	u8 cmd;
	u16 raw;
};
static struct cm3232_priv *cm3232_obj;

static int cm3232_read_raw(struct cm3232_priv *obj, u16 *raw)
{
	s32 ret = i2c_smbus_read_word_data(obj->client, CM3232_REG_ALS);
	if (ret < 0) return ret;
	*raw = (u16)ret;
	return 0;
}
static int cm3232_set_enabled(struct cm3232_priv *obj, bool enable)
{
	int ret; u8 cmd;
	mutex_lock(&obj->lock); cmd = obj->cmd;
	if (enable) cmd &= ~CM3232_CMD_DISABLE; else cmd |= CM3232_CMD_DISABLE;
	ret = i2c_smbus_write_byte_data(obj->client, CM3232_REG_CMD, cmd);
	if (!ret) obj->cmd = cmd;
	mutex_unlock(&obj->lock); return ret;
}
static int cm3232_map_value(struct cm3232_priv *obj, u16 raw)
{
	int i;
	for (i = 0; i < C_CUST_ALS_LEVEL - 1; i++) {
		if (obj->hw.als_level[i] == 0 && obj->hw.als_value[i] == 0) break;
		if (raw < obj->hw.als_level[i]) break;
	}
	if (i < C_CUST_ALS_LEVEL && obj->hw.als_value[i] != 0)
		return obj->hw.als_value[i];
	return (raw * 1785U) / 10000U;
}
static int cm3232_open_report_data(int open) { return 0; }
static int cm3232_enable_nodata(int en)
{
	if (!cm3232_obj) return -ENODEV;
	pr_info("als enable=%d\n", en);
	return cm3232_set_enabled(cm3232_obj, en != 0);
}
static int cm3232_set_delay(u64 ns) { return 0; }
static int cm3232_batch(int flag, int64_t period, int64_t latency)
{ return cm3232_set_delay(period); }
static int cm3232_flush(void) { return als_flush_report(); }
static int cm3232_get_data(int *value, int *status)
{
	u16 raw; int ret;
	if (!cm3232_obj) return -ENODEV;
	ret = cm3232_read_raw(cm3232_obj, &raw); if (ret < 0) return ret;
	cm3232_obj->raw = raw; *value = cm3232_map_value(cm3232_obj, raw);
	*status = SENSOR_STATUS_ACCURACY_MEDIUM; return 0;
}
static int cm3232_get_raw_data(int *value)
{
	u16 raw; int ret;
	if (!cm3232_obj) return -ENODEV;
	ret = cm3232_read_raw(cm3232_obj, &raw); if (ret < 0) return ret;
	cm3232_obj->raw = raw; *value = raw; return 0;
}
static int cm3232_ps_open_report_data(int open) { return 0; }
static int cm3232_ps_enable_nodata(int en) { return 0; }
static int cm3232_ps_set_delay(u64 ns) { return 0; }
static int cm3232_ps_batch(int flag, int64_t period, int64_t latency)
{ return cm3232_ps_set_delay(period); }
static int cm3232_ps_flush(void) { return ps_flush_report(); }
static int cm3232_ps_get_data(int *value, int *status)
{
	/* CM3232 is ALS-only; register the PS endpoint for HAL compatibility. */
	return -ENODEV;
}
static const struct of_device_id cm3232_of_match[] = {
	{ .compatible = "mediatek,alsps" }, { }
};
MODULE_DEVICE_TABLE(of, cm3232_of_match);
static const struct i2c_device_id cm3232_i2c_id[] = {
	{ CM3232_DEV_NAME, 0 }, { }
};
MODULE_DEVICE_TABLE(i2c, cm3232_i2c_id);
static int cm3232_i2c_probe(struct i2c_client *client, const struct i2c_device_id *id)
{
	struct cm3232_priv *obj; struct als_control_path ctl = {0};
	struct als_data_path data = {0}; int ret; s32 chip_id;
	obj = kzalloc(sizeof(*obj), GFP_KERNEL); if (!obj) return -ENOMEM;
	mutex_init(&obj->lock); obj->client = client;
	ret = get_alsps_dts_func(client->dev.of_node, &obj->hw); if (ret < 0) goto err;
	i2c_set_clientdata(client, obj);
	ret = i2c_smbus_write_byte_data(client, CM3232_REG_CMD,
		CM3232_CMD_DISABLE | CM3232_CMD_RESET); if (ret < 0) goto err;
	msleep(5); chip_id = i2c_smbus_read_word_data(client, CM3232_REG_ID);
	if (chip_id < 0 || (chip_id & 0xff) != CM3232_HW_ID) {
		pr_err("unexpected chip id 0x%x\n", chip_id); ret = -ENODEV; goto err;
	}
	obj->cmd = CM3232_CMD_DEFAULT;
	ret = i2c_smbus_write_byte_data(client, CM3232_REG_CMD, obj->cmd); if (ret < 0) goto err;
	cm3232_obj = obj;
	ctl.open_report_data = cm3232_open_report_data; ctl.enable_nodata = cm3232_enable_nodata;
	ctl.set_delay = cm3232_set_delay; ctl.batch = cm3232_batch; ctl.flush = cm3232_flush;
	ctl.is_report_input_direct = false; ctl.is_support_batch = false; ctl.is_use_common_factory = true;
	ret = als_register_control_path(&ctl); if (ret < 0) goto err_obj;
	data.get_data = cm3232_get_data; data.als_get_raw_data = cm3232_get_raw_data; data.vender_div = 1;
	ret = als_register_data_path(&data); if (ret < 0) goto err_obj;
	{
		struct ps_control_path ps_ctl = {0};
		struct ps_data_path ps_data = {0};
		ps_ctl.open_report_data = cm3232_ps_open_report_data;
		ps_ctl.enable_nodata = cm3232_ps_enable_nodata;
		ps_ctl.set_delay = cm3232_ps_set_delay;
		ps_ctl.batch = cm3232_ps_batch;
		ps_ctl.flush = cm3232_ps_flush;
		ps_ctl.is_report_input_direct = false;
		ps_ctl.is_support_batch = false;
		ret = ps_register_control_path(&ps_ctl); if (ret < 0) goto err_obj;
		ps_data.get_data = cm3232_ps_get_data; ps_data.vender_div = 1;
		ret = ps_register_data_path(&ps_data); if (ret < 0) goto err_obj;
	}
	pr_info("probe ok on i2c-%d addr 0x%02x, id 0x%02x\n", client->adapter->nr, client->addr, chip_id & 0xff);
	return 0;
err_obj: cm3232_obj = NULL;
err: kfree(obj); return ret;
}
static int cm3232_i2c_remove(struct i2c_client *client)
{
	struct cm3232_priv *obj = i2c_get_clientdata(client);
	if (obj) cm3232_set_enabled(obj, false);
	if (cm3232_obj == obj) cm3232_obj = NULL; kfree(obj); return 0;
}
static struct i2c_driver cm3232_i2c_driver = {
	.probe = cm3232_i2c_probe, .remove = cm3232_i2c_remove, .id_table = cm3232_i2c_id,
	.driver = { .name = CM3232_DEV_NAME, .of_match_table = cm3232_of_match },
};
static int cm3232_local_init(void) { return i2c_add_driver(&cm3232_i2c_driver); }
static int cm3232_remove(void) { i2c_del_driver(&cm3232_i2c_driver); return 0; }
static struct alsps_init_info cm3232_init_info = {
	.name = CM3232_DEV_NAME, .init = cm3232_local_init, .uninit = cm3232_remove,
};
static int __init cm3232_init(void) { alsps_driver_add(&cm3232_init_info); return 0; }
module_init(cm3232_init);
MODULE_AUTHOR("agui4541 / OpenAI");
MODULE_DESCRIPTION("Capella CM3232 MediaTek ALSPS driver");
MODULE_LICENSE("GPL v2");
