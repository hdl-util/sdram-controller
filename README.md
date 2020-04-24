# AS4C4M16SA Synchronous DRAM Controller

[![Build Status](https://travis-ci.com/hdl-util/as4c4m16sa.svg?branch=master)](https://travis-ci.com/hdl-util/as4c4m16sa)

## Why?

The SDRAM controller Arduino uses for this chip is proprietary Intel IP: `altera_avalon_new_sdram_controller`. The code in this repository lets you control the DRAM chip without licensing an IP block from anyone. Now, Quartus Prime Lite users can freely make their own designs.

## Usage

1. Take files from `src/` and add them to your own project. If you use [hdlmake](https://hdlmake.readthedocs.io/en/master/), you can add this repository itself as a remote module.
1. Other helpful modules are also available in this GitHub organization.
1. See `top/mkrvidor4000_quartus/mkrvidor4000_top.sv` for a usage example, where each address is written with its 16 least significant bits and replayed to verify.
1. Read through the parameters in `as4c4m16sa.sv` and tailor any instantiations to your situation.
1. Please create an issue if you run into a problem or have any questions. Make sure you have consulted the troubleshooting section first.

### Terminology

* **CAS latency**: the time (in clocks) for a read command to return data
* **Precharge**: a required step in DRAM operation that sets the line voltage to Vcc / 2 (3.3V / 2) in anticipation of the next operation
* **Refresh**: restores the charge in the cells by rewriting them

### Troubleshooting

* Make sure you've set the IO standard for the pins connected to the DRAM chip as LVTTL 3.3V
* If you are using SystemVerilog, make sure you use `wire` instead of `logic` for DQ and the clock. This caused synthesis issues claiming that the pins were stuck at GND or VCC when they were clearly being driven.

## To-do List

* Self Refresh Mode
* Optimizations
    * [ ] Manual precharging
        * Auto precharging predicts the next memory access will be on a diferent page
        * Manual precharging assumes spatial locality
    * [ ] Bank activation: if the row address and bank are the same, can you do a repeated read/write?
    * [ ] Command pipelining: you can activate another bank while a write/read is being done



## Reference Documents

These documents are not hosted here! They are available directly from Alliance Memory.

* [AS4C4M16SA 6 or 7 Datasheet](https://www.alliancememory.com/wp-content/uploads/pdf/dram/64M-AS4C4M16SA-CI_v3.0_March%202015.pdf)
* [AS4C4M16SA 5 Datasheet](https://www.alliancememory.com/wp-content/uploads/pdf/dram/AllianceMemory-64M_SDRAM_A_Rev_AS4C4M16SA-5TCN_December2016v1.0.pdf)
