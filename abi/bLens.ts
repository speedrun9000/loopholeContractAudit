export const bLens = [
  {
    type: 'function',
    name: 'LABEL',
    inputs: [],
    outputs: [
      { name: '', type: 'bytes32', internalType: 'bytes32' },
    ],
    stateMutability: 'view',
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
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'accumulator',
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
    name: 'activePrice',
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
    name: 'blvPrice',
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
    name: 'claimableYield',
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
    name: 'convexityExp',
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
    name: 'creator',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      { name: '', type: 'address', internalType: 'address' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'creatorClaimable',
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
    name: 'creatorFeePct',
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
    name: 'creditAccount',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_user', type: 'address', internalType: 'address' },
    ],
    outputs: [
      { name: '', type: 'uint256', internalType: 'uint256' },
      { name: '', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getBookPrice',
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
    name: 'getCirculatingSupply',
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
    name: 'getComponents',
    inputs: [],
    outputs: [
      { name: 'components_', type: 'address[]', internalType: 'contract Component[]' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getMaker',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      {
        name: '',
        type: 'tuple',
        internalType: 'struct State.Maker',
        components: [
          { name: 'initialized', type: 'bool', internalType: 'bool' },
          { name: 'blvPrice', type: 'uint128', internalType: 'uint128' },
          { name: 'swapFee', type: 'uint128', internalType: 'uint128' },
          { name: 'maxCirc', type: 'uint128', internalType: 'uint128' },
          { name: 'maxReserves', type: 'uint128', internalType: 'uint128' },
          { name: 'convexityExp', type: 'uint128', internalType: 'uint128' },
          { name: 'lastInvariant', type: 'uint128', internalType: 'uint128' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'hasHook',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      { name: '', type: 'bool', internalType: 'bool' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'isApprovedCreditDeployer',
    inputs: [
      { name: '_user', type: 'address', internalType: 'address' },
    ],
    outputs: [
      { name: '', type: 'bool', internalType: 'bool' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'isLocked',
    inputs: [],
    outputs: [
      { name: '', type: 'bool', internalType: 'bool' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'isPoolPaused',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      { name: '', type: 'bool', internalType: 'bool' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'isProtocolPaused',
    inputs: [],
    outputs: [
      { name: '', type: 'bool', internalType: 'bool' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'lastInvariant',
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
    name: 'lastUpdatedTimestamp',
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
    name: 'originationFee',
    inputs: [],
    outputs: [
      { name: '', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'pendingYield',
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
    name: 'poolFeeRecipient',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      { name: '', type: 'address', internalType: 'address' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'poolFeeShare',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      { name: 'creator_', type: 'uint256', internalType: 'uint256' },
      { name: 'staking_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'poolIdToBToken',
    inputs: [
      { name: '_poolId', type: 'bytes32', internalType: 'PoolId' },
    ],
    outputs: [
      { name: '', type: 'address', internalType: 'contract BToken' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'poolKey',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      {
        name: '',
        type: 'tuple',
        internalType: 'struct PoolKey',
        components: [
          { name: 'currency0', type: 'address', internalType: 'Currency' },
          { name: 'currency1', type: 'address', internalType: 'Currency' },
          { name: 'fee', type: 'uint24', internalType: 'uint24' },
          { name: 'tickSpacing', type: 'int24', internalType: 'int24' },
          { name: 'hooks', type: 'address', internalType: 'contract IHooks' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'protocolClaimable',
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
    name: 'protocolFeePct',
    inputs: [],
    outputs: [
      { name: '', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'protocolFeeRecipient',
    inputs: [],
    outputs: [
      { name: '', type: 'address', internalType: 'address' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'quoteLeverage',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_collateralIn', type: 'uint256', internalType: 'uint256' },
      { name: '_leverageFactor', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [
      { name: 'targetCollateral_', type: 'uint256', internalType: 'uint256' },
      { name: 'maxSwapReservesIn_', type: 'uint256', internalType: 'uint256' },
      { name: 'expectedDebt_', type: 'uint256', internalType: 'uint256' },
      { name: 'slippage_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'reserve',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      { name: '', type: 'address', internalType: 'contract ERC20' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'reserveHoldings',
    inputs: [
      { name: '_reserve', type: 'address', internalType: 'contract ERC20' },
    ],
    outputs: [
      { name: '', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'stakedPosition',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_user', type: 'address', internalType: 'address' },
    ],
    outputs: [
      { name: '', type: 'uint256', internalType: 'uint256' },
      { name: '', type: 'uint256', internalType: 'uint256' },
      { name: '', type: 'uint256', internalType: 'uint256' },
      { name: '', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
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
    name: 'swapFee',
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
    name: 'timeToAdapt',
    inputs: [],
    outputs: [
      { name: '', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'timeToDistribute',
    inputs: [],
    outputs: [
      { name: '', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'tokensPerSecond',
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
    name: 'totalBTokens',
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
    name: 'totalCollateral',
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
    name: 'totalDebt',
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
    name: 'totalFeeShare',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [
      { name: 'creator_', type: 'uint256', internalType: 'uint256' },
      { name: 'staking_', type: 'uint256', internalType: 'uint256' },
      { name: 'protocol_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'totalReserves',
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
    name: 'totalStaked',
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
    name: 'totalSupply',
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
    name: 'withdrawable',
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
    type: 'error',
    name: 'BLens_InvalidLeverageFactor',
    inputs: [],
  },
  {
    type: 'error',
    name: 'Component_NotPermitted',
    inputs: [],
  },
] as const;
