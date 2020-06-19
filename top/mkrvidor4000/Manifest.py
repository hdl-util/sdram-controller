files = [
    "mkrvidor4000_top.sv"
]

modules = {
    "git": [
        "git@github.com:hdl-util/hdmi.git::master",
        "git@github.com:hdl-util/sound.git::master",
        "git@github.com:hdl-util/vga-text-mode.git::master",
        "git@github.com:hdl-util/clock-domain-crossing.git::master"
    ],
    "local" : [ "../../src/" ]
}

fetchto = "../../ip_cores"
