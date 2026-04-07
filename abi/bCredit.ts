export const bCredit = [
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
    name: 'borrow',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_amount', type: 'uint256', internalType: 'uint256' },
      { name: '_recipient', type: 'address', internalType: 'address' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'borrowNative',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_amount', type: 'uint256', internalType: 'uint256' },
      { name: '_recipient', type: 'address', internalType: 'address' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'claimCredit',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_users', type: 'address[]', internalType: 'address[]' },
      { name: '_collaterals', type: 'uint128[]', internalType: 'uint128[]' },
      { name: '_debts', type: 'uint128[]', internalType: 'uint128[]' },
      { name: '_proofs', type: 'bytes32[][]', internalType: 'bytes32[][]' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'defaultSelf',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'deleverage',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_collateralToSell', type: 'uint256', internalType: 'uint256' },
      { name: '_minSwapReservesOut', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [
      { name: 'collateralRedeemed_', type: 'uint256', internalType: 'uint256' },
      { name: 'debtRepaid_', type: 'uint256', internalType: 'uint256' },
      { name: 'refund_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'getBorrowForCollateral',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_collateral', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [
      { name: 'borrowAmount_', type: 'uint256', internalType: 'uint256' },
      { name: 'fee_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getMaxBorrow',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_user', type: 'address', internalType: 'address' },
    ],
    outputs: [
      { name: 'maxBorrow_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'leverage',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_totalCollateral', type: 'uint256', internalType: 'uint256' },
      { name: '_collateralIn', type: 'uint256', internalType: 'uint256' },
      { name: '_maxSwapReservesIn', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [
      { name: 'debt_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'previewBorrow',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_user', type: 'address', internalType: 'address' },
      { name: '_borrowAmount', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [
      { name: 'collateral_', type: 'uint256', internalType: 'uint256' },
      { name: 'debt_', type: 'uint256', internalType: 'uint256' },
      { name: 'fee_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'previewDepositAndBorrow',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_user', type: 'address', internalType: 'address' },
      { name: '_depositAmount', type: 'uint256', internalType: 'uint256' },
      { name: '_borrowAmount', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [
      { name: 'collateral_', type: 'uint256', internalType: 'uint256' },
      { name: 'debt_', type: 'uint256', internalType: 'uint256' },
      { name: 'fee_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'previewRepay',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_recipient', type: 'address', internalType: 'address' },
      { name: '_reservesIn', type: 'uint256', internalType: 'uint256' },
    ],
    outputs: [
      { name: 'collateralRedeemed_', type: 'uint256', internalType: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'repay',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_reservesIn', type: 'uint256', internalType: 'uint256' },
      { name: '_recipient', type: 'address', internalType: 'address' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'repayWithNative',
    inputs: [
      { name: '_bToken', type: 'address', internalType: 'contract BToken' },
      { name: '_recipient', type: 'address', internalType: 'address' },
    ],
    outputs: [],
    stateMutability: 'payable',
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
    type: 'event',
    name: 'Borrow',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'contract BToken',
      },
      { name: 'user', type: 'address', indexed: false, internalType: 'address' },
      { name: 'borrowed', type: 'uint256', indexed: false, internalType: 'uint256' },
      { name: 'fee', type: 'uint256', indexed: false, internalType: 'uint256' },
      {
        name: 'post',
        type: 'tuple',
        indexed: false,
        internalType: 'struct State.CreditAccount',
        components: [
          { name: 'collateral', type: 'uint128', internalType: 'uint128' },
          { name: 'debt', type: 'uint128', internalType: 'uint128' },
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'CreditClaim',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'contract BToken',
      },
      { name: 'users', type: 'address[]', indexed: false, internalType: 'address[]' },
      {
        name: 'collaterals',
        type: 'uint128[]',
        indexed: false,
        internalType: 'uint128[]',
      },
      { name: 'debts', type: 'uint128[]', indexed: false, internalType: 'uint128[]' },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'DefaultSelf',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'contract BToken',
      },
      { name: 'user', type: 'address', indexed: false, internalType: 'address' },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Deleverage',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'contract BToken',
      },
      { name: 'user', type: 'address', indexed: false, internalType: 'address' },
      {
        name: 'collateralRedeemed',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      { name: 'debtRepaid', type: 'uint256', indexed: false, internalType: 'uint256' },
      {
        name: 'collateralSold',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      { name: 'refund', type: 'uint256', indexed: false, internalType: 'uint256' },
      {
        name: 'post',
        type: 'tuple',
        indexed: false,
        internalType: 'struct State.CreditAccount',
        components: [
          { name: 'collateral', type: 'uint128', internalType: 'uint128' },
          { name: 'debt', type: 'uint128', internalType: 'uint128' },
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Distributed',
    inputs: [
      { name: 'bToken', type: 'address', indexed: false, internalType: 'address' },
      { name: 'reserve', type: 'address', indexed: false, internalType: 'address' },
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
      { name: 'creatorFee', type: 'uint256', indexed: false, internalType: 'uint256' },
      { name: 'stakingFee', type: 'uint256', indexed: false, internalType: 'uint256' },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Leverage',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'contract BToken',
      },
      { name: 'user', type: 'address', indexed: false, internalType: 'address' },
      {
        name: 'collateralAdded',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      { name: 'debtAdded', type: 'uint256', indexed: false, internalType: 'uint256' },
      {
        name: 'collateralIn',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      { name: 'reservesIn', type: 'uint256', indexed: false, internalType: 'uint256' },
      {
        name: 'post',
        type: 'tuple',
        indexed: false,
        internalType: 'struct State.CreditAccount',
        components: [
          { name: 'collateral', type: 'uint128', internalType: 'uint128' },
          { name: 'debt', type: 'uint128', internalType: 'uint128' },
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: 'event',
    name: 'Repay',
    inputs: [
      {
        name: 'bToken',
        type: 'address',
        indexed: false,
        internalType: 'contract BToken',
      },
      { name: 'user', type: 'address', indexed: false, internalType: 'address' },
      {
        name: 'collateralRedeemed',
        type: 'uint256',
        indexed: false,
        internalType: 'uint256',
      },
      { name: 'debtRepaid', type: 'uint256', indexed: false, internalType: 'uint256' },
      {
        name: 'post',
        type: 'tuple',
        indexed: false,
        internalType: 'struct State.CreditAccount',
        components: [
          { name: 'collateral', type: 'uint128', internalType: 'uint128' },
          { name: 'debt', type: 'uint128', internalType: 'uint128' },
        ],
      },
    ],
    anonymous: false,
  },
  {
    type: 'error',
    name: 'BCredit_AlreadyClaimed',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_CannotRepayContract',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_Deleverage_InvalidCollateralToSell',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_Deleverage_Undercollateralized',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_InsufficientCollateral',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_InvalidClaim',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_InvalidClaimLength',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_InvalidProof',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_Leverage_BorrowAmountTooLow',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_Leverage_InvalidStakedAmount',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_Leverage_ZeroCollateral',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_NoClaimMerkleRoot',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_RepaidMoreThanDebt',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_SystemClaim_Undercollateralized',
    inputs: [],
  },
  {
    type: 'error',
    name: 'BCredit_UserClaim_Undercollateralized',
    inputs: [],
  },
  {
    type: 'error',
    name: 'CollateralLib_InsufficientStake',
    inputs: [],
  },
  {
    type: 'error',
    name: 'Component_NotPermitted',
    inputs: [],
  },
  {
    type: 'error',
    name: 'GuardLib_Insolvent',
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
  {
    type: 'error',
    name: 'NativeLib_AmountMismatch',
    inputs: [],
  },
  {
    type: 'error',
    name: 'NativeLib_NotWrapped',
    inputs: [],
  },
] as const;
