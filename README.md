# AES-Scalar-Crypto
This repository includes a first-order side-channel attack (SCA) secure advanced encryption standard (AES) accelerator designed following the RISC-V [Scalar-Crypto instruction set extension (ISE)](https://github.com/riscv/riscv-crypto). The accelerator implements a 2 share flow with a [domain oriented masking (DOM)](https://eprint.iacr.org/2016/486) scheme. Furthermore, there is a wrapper that connects the accelerator to the [eXtension Interface (XIF)](https://github.com/openhwgroup/core-v-xif).

Microarchitectures and design descriptions can be found in [masters thesis](https://ntnuopen.ntnu.no/ntnu-xmlui/handle/11250/3023096). 
