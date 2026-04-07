import type { Address } from 'viem';

const BASE_ID = 8453;
const BASE_SEPOLIA_ID = 84532;

// #region Reserves

export enum ApprovedReserves {
  WETH = 0,
  CBBTC = 1,
}

export const addressToReserve: Record<
  number,
  Record<Address, ApprovedReserves>
> = {
  [BASE_SEPOLIA_ID]: {
    '0xB85885897D297000A74eA2e4711C3Ca729461ABC': ApprovedReserves.WETH,
    '0x3dC8abEEc934A8c318E0a8c84867bb47ecB2A22a': ApprovedReserves.CBBTC,
  },
};

const priceFeedAddress: Record<number, Record<ApprovedReserves, Address>> = {
  [BASE_ID]: {
    [ApprovedReserves.WETH]: '0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70',
    [ApprovedReserves.CBBTC]: '0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D',
  },
  [BASE_SEPOLIA_ID]: {
    [ApprovedReserves.WETH]: '0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1',
    [ApprovedReserves.CBBTC]: '0x3c65e28D357a37589e1C7C86044a9f44dDC17134',
  },
};

export const getReservePriceFeed = (chainId: number, address: Address) => {
  console.log('chain id', chainId, 'address', address);
  const reserve = addressToReserve[chainId]?.[address];
  if (reserve === undefined) {
    throw new Error(
      `Reserve not found for address ${address} on chain ${chainId}`,
    );
  }
  const priceFeed = priceFeedAddress[chainId]?.[reserve];
  if (priceFeed === undefined) {
    throw new Error(
      `Price feed not found for address ${address} on chain ${chainId}`,
    );
  }
  return priceFeed;
};

// #endregion Reserves

export type ContractDeployment = {
  address: Address;
  block: number;
};

// Relay contract deployments
export const relayDeployments = {
  [BASE_SEPOLIA_ID]: {
    address: '0xf020C709fe9Ae902e3CDED1E50CA01021ce968E8' as Address,
    block: 38018695,
  },
} satisfies Record<number, ContractDeployment>;
