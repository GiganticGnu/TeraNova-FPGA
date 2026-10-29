Baseline measurement logs (TeraNova FPGA project)

One PuTTY log per execution of the measurement app:
  baseline0_O2_run1.txt .. run3.txt   previous group's bitstream (30 Sep), -O2
  baseline0_O0.txt                    same bitstream, -O0 build (optional)
  baseline1_O2_run1.txt .. run3.txt   restored design (Badr's build), -O2
  baseline1_utilization.rpt           from Badr's build
  baseline1_timing.rpt                from Badr's build

Lines starting with "CSV," can be pasted into a spreadsheet and split on commas:
  CSV,cpu,first_ns,best_ns
  CSV,probe,write_ns,read_ns,ddr_read_ns
  CSV,run,run,load_ns,compute_ns,readback_ns,total_ns,mismatches,detector
      detector: 0 = interrupt, 1 = GPIO poll (+-1 us), 2 = not seen
  CSV,summary,passed,irq_runs,gpio_runs,not_seen
