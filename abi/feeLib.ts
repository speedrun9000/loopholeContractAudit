export const feeLib = [
  {
    type: 'event',
    name: 'Distributed',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'reserve',
        type: 'address',
        indexed: false,
        internalType: 'address',
      },
      {
        name: 'totalAmount',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      {
        name: 'protocolFee',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      {
        name: 'creatorFee',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      {
        name: 'stakingFee',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
    ],
    anonymous: false,
  },
] as const;
