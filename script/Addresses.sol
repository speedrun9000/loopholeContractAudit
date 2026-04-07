// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Addresses {
    // ── Base Sepolia (84532) ──────────────────────────────────────

    // External
    address constant BASELINE = 0xf020C709fe9Ae902e3CDED1E50CA01021ce968E8;
    address constant BASELINE_ADMIN = 0xe5393AA43106210e50CF8540Bab4F764079bE355;
    address constant BASELINE_WETH = 0xB85885897D297000A74eA2e4711C3Ca729461ABC;

    // PresaleFactory (UUPS)
    address constant FACTORY_PROXY = 0x82678FDCAD0d9795cc0c440945407C325c2273Fc;
    address constant FACTORY_IMPL = 0x6cB041fA435571eF78Ba59caad5B21b6EaF5c73D;

    // Presale beacon system
    address constant BEACON = 0x36D5470D2e49307Bd4cE42AD69C3a49CCB78Fb64;
    address constant PRESALE_IMPL = 0x5ED5a068633c959d42E30EF86B9Ed25c4483aC8d;

    // ProjectFeeRouter (UUPS)
    address constant FEE_ROUTER_PROXY = 0xC996F3484FE1DfDac69E63D52838385A21E53Bb8;
    address constant FEE_ROUTER_IMPL = 0x905c87D81a0ee64A9dFb3a67EE084249B4aecc75;

    // Roles
    address constant ADMIN = 0xc25af38A36d790F34176955Fc81dee87aDBA071B;
}
