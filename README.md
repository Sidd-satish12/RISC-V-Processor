# Out-of-Order RISC-V Processor

This repository contains a custom **out-of-order, superscalar RISC-V processor** implemented in **SystemVerilog**, designed with a focus on realistic microarchitectural behavior, modular verification, and synthesizability.

The project explores how modern processors extract instruction-level parallelism using **dynamic scheduling, speculation, and precise state retirement**, while remaining fully verifiable through simulation and synthesis flows.

---

## Project Overview

The processor follows a **decoupled frontend/backend architecture** and supports **out-of-order execution with in-order retirement**. Development was carried out incrementally, beginning with individual microarchitectural components and scaling to a fully integrated CPU capable of running non-trivial RISC-V programs.

Key goals of the project include:
- Correct and precise architectural state
- Performance-aware microarchitecture design
- Modular, testbench-driven verification
- Realistic modeling of memory latency and caching

---

## Features

### Execution Model
- Out-of-order instruction execution  
- In-order commit with precise exceptions  
- Register renaming and dependency tracking  
- Speculative execution support  

### Core Microarchitecture Components
- Reservation Stations (RS)  
- Reorder Buffer (ROB)  
- Integer ALU  
- Pipelined multiplier with configurable depth  
- Centralized commit and retirement logic  

### Memory System
- Instruction cache with tagged memory responses  
- Explicit memory latency modeling  
- Cache-aware memory interface  
- Correct writeback of dirty cache data  

### Verification and Tooling
- Standalone testbenches for individual modules  
- Simulation and synthesized simulation support  
- Coverage-driven verification  
- Automated pass/fail detection  
- CPI, writeback, and pipeline trace generation  

