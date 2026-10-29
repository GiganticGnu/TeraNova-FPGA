# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "")
  file(REMOVE_RECURSE
  "C:\\PLD\\S7_integration_vit\\interrupt_rerun_plat\\psu_cortexa53_0\\standalone_psu_cortexa53_0\\bsp\\include\\sleep.h"
  "C:\\PLD\\S7_integration_vit\\interrupt_rerun_plat\\psu_cortexa53_0\\standalone_psu_cortexa53_0\\bsp\\include\\xiltimer.h"
  "C:\\PLD\\S7_integration_vit\\interrupt_rerun_plat\\psu_cortexa53_0\\standalone_psu_cortexa53_0\\bsp\\include\\xtimer_config.h"
  "C:\\PLD\\S7_integration_vit\\interrupt_rerun_plat\\psu_cortexa53_0\\standalone_psu_cortexa53_0\\bsp\\lib\\libxiltimer.a"
  )
endif()
