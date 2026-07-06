#include <basu/sd-bus.h>

static inline int enter_variant(sd_bus_message *m, const char **contents) {
    return sd_bus_message_enter_container(m, SD_BUS_TYPE_VARIANT, (const char *)contents);
}

static inline int enter_array(sd_bus_message *m, const char *contents) {
    return sd_bus_message_enter_container(m, SD_BUS_TYPE_ARRAY, contents);
}

static inline int enter_dict_entry(sd_bus_message *m, const char *contents) {
    return sd_bus_message_enter_container(m, SD_BUS_TYPE_DICT_ENTRY, contents);
}
