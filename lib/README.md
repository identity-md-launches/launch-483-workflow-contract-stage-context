# Vendored dependencies

- `openzeppelin-contracts`: OpenZeppelin/openzeppelin-contracts `v5.0.2`; 6 vendored source/license files.
  Archive: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
  Archive SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`.

- `forge-std`: foundry-rs/forge-std `v1.9.7`; 30 vendored source/license files.
  Archive: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
  Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.

OpenZeppelin includes only the unmodified ERC-20 dependency closure and its license.
forge-std includes the complete unmodified src tree and both licenses.
These are ordinary files, not submodules; builds need no dependency downloads.
