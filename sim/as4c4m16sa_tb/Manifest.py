action = "simulation"
sim_tool = "modelsim"
sim_top = "as4c4m16sa_tb"

sim_post_cmd = "vsim -novopt -do ../vsim.do -c as4c4m16sa_tb"

modules = {
  "local" : [ "../../test/" ],
}
