export const bStaking = [
  {
    type: 'function',
    name: 'LABEL',
    inputs: [],
    outputs: [
      { name: '', type: 'bytes32', internalType: 'bytes32' },
    ],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    name: 'ROUTES',
    inputs: [],
    outputs: [
      { name: 'routes_', type: 'bytes4[]', internalType: 'bytes4[]' },
    ],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    name: 'VERSION',
    inputs: [],
    outputs: [
      { name: '', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    name: 'claim',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_user', type: 'address', internalType: 'address' },
      { name: '_asNative', type: 'bool', internalType: 'bool' },
    ],
    outputs: [
      { name: 'amount_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'deposit',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_user', type: 'address', internalType: 'address' },
      { name: '_amount', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'getAccumulator',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      { name: 'accumulator_', type: 'uint256', internalType: 'uint256' },
      { name: 'newYield_', type: 'uint256', internalType: 'uint256' },
      { name: 'tokensPerSecond_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getCurrentRate',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      { name: '', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getEarned',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_user', type: 'address', internalType: 'address' },
    ],
    outputs: [
      { name: '', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'liquidate',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_user', type: 'address', internalType: 'address' },
      { name: '_amount', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'supportsInterface',
    inputs: [
      { name: '_interfaceId', type: 'bytes4', internalType: 'bytes4' },
    ],
    outputs: [
      { name: '', type: 'bool', internalType: 'bool' },
    ],
    stateMutability: 'pure',
  },
  {
    type: 'function',
    name: 'withdraw',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_amount', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'withdrawAndClaim',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_amount', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'withdrawMax',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'event',
    name: 'Claim',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'contract BToken',
      },
      { name: 'user', type: 'address', indexed: false, internalType: 'address' },
      { name: 'amount', type: 'uint256', indexed: false, internalType: 'uint256' },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Deposit',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'contract BToken',
      },
      { name: 'user', type: 'address', indexed: false, internalType: 'address' },
      { name: 'amount', type: 'uint256', indexed: false, internalType: 'uint256' },
      {
        name: 'post',
        type: 'tuple',
        indexed: false,
        internalType: 'struct State.StakedAccount',
        components: [
          { name: 'amount', type: 'uint128', internalType: 'uint128' },
          { name: 'locked', type: 'uint128', internalType: 'uint128' },
          { name: 'earned', type: 'uint128', internalType: 'uint128' },
          { name: 'userAccumulator', type: 'uint256', internalType: 'uint256' },
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Liquidate',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'contract BToken',
      },
      { name: 'user', type: 'address', indexed: false, internalType: 'address' },
      { name: 'amount', type: 'uint256', indexed: false, internalType: 'uint256' },
      {
        name: 'post',
        type: 'tuple',
        indexed: false,
        internalType: 'struct State.StakedAccount',
        components: [
          { name: 'amount', type: 'uint128', internalType: 'uint128' },
          { name: 'locked', type: 'uint128', internalType: 'uint128' },
          { name: 'earned', type: 'uint128', internalType: 'uint128' },
          { name: 'userAccumulator', type: 'uint256', internalType: 'uint256' },
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Withdraw',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'contract BToken',
      },
      { name: 'user', type: 'address', indexed: false, internalType: 'address' },
      { name: 'amount', type: 'uint256', indexed: false, internalType: 'uint256' },
      {
        name: 'post',
        type: 'tuple',
        indexed: false,
        internalType: 'struct State.StakedAccount',
        components: [
          { name: 'amount', type: 'uint128', internalType: 'uint128' },
          { name: 'locked', type: 'uint128', internalType: 'uint128' },
          { name: 'earned', type: 'uint128', internalType: 'uint128' },
          { name: 'userAccumulator', type: 'uint256', internalType: 'uint256' },
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: 'error',
    name: 'BStaking_BTokenNotInitialized',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BStaking_StakeIsLocked',
    inputs: [],
  },
  {
    type: 'error',
    name: 'Component_NotPermitted',
    inputs: [],
  },
  {
    type: 'error',
    name: 'GuardLib_InvalidCirculatingSupply',
    inputs: [],
  },
  {
    type: 'error',
    name: 'GuardLib_Paused',
    inputs: [],
  },
  {
    type: 'error',
    name: 'GuardLib_Reentrant',
    inputs: [],
  },
] as const;
