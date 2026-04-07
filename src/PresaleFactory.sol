// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPresale} from "./interfaces/IPresale.sol";
import {PresaleImplementation} from "./PresaleImplementation.sol";
import {BFactory} from "./interfaces/IBFactory.sol";

/**
 * @title PresaleFactory
 * @notice UUPS upgradeable factory for deploying and managing presale contracts.
 *         Routes bToken + pool creation through this contract so only the factory
 *         needs to be whitelisted on Baseline.
 * @dev Uses OpenZeppelin's UpgradeableBeacon for upgradeability across all presales
 */
contract PresaleFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PresaleDeployed(
        address indexed presale, address indexed creator, uint256 phaseCount, IPresale.SaleType saleType
    );
    event BeaconUpgraded(address indexed newImplementation);
    event PresaleBeaconModified(IBeacon indexed previousBeacon, IBeacon indexed newBeacon);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidImplementation();
    error BFactoryNotSet();
    error DeploymentFailed();
    error InvalidAdmin();
    error UnauthorizedPresale();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Upgradeable beacon which new Presales deployed by this contract point to
    IBeacon public presaleBeacon;

    /// @notice Array of all deployed presale contracts
    address[] public presales;

    /// @notice Mapping to check if an address is a deployed presale
    mapping(address => bool) public isPresale;

    /// @notice Address of the BFactory contract
    BFactory public bFactory;

    /// @dev Storage gap for future upgrades
    uint256[50] private __gap;

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the factory
     * @param _presaleBeacon The UpgradeableBeacon managing presale implementation logic
     * @param _bFactoryAddress The BFactory contract for token and pool creation
     * @param _initialAdmin The owner address
     */
    function initialize(IBeacon _presaleBeacon, BFactory _bFactoryAddress, address _initialAdmin) external initializer {
        if (address(_presaleBeacon) == address(0)) revert InvalidImplementation();
        if (address(_bFactoryAddress) == address(0)) revert BFactoryNotSet();
        if (_initialAdmin == address(0)) revert InvalidAdmin();

        __Ownable_init(_initialAdmin);
        __UUPSUpgradeable_init();

        bFactory = _bFactoryAddress;
        _setPresaleBeacon(_presaleBeacon);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy a new presale contract
     * @param phases Array of phase configurations
     * @param config General presale configuration
     * @param bFactoryParams Parameters for token and pool creation
     * @param presaleToken Address of the ERC20 token used for presale deposits
     * @return presale Address of the deployed presale contract
     */
    function deployPresale(
        IPresale.PresalePhaseConfig[] memory phases,
        IPresale.PresaleConfig memory config,
        IPresale.BFactoryParams memory bFactoryParams,
        address presaleToken
    ) external onlyOwner returns (address presale) {
        // Pass address(this) as the factory so presales route pool creation through us
        // (only the factory needs to be whitelisted on Baseline)
        bytes memory initCalldata = abi.encodeWithSelector(
            PresaleImplementation.initialize.selector, phases, config, bFactoryParams, address(this), presaleToken
        );

        // Deploy the BeaconProxy pointing at the presale beacon, passing in initialization calldata
        BeaconProxy presaleProxy = new BeaconProxy(address(presaleBeacon), initCalldata);
        presale = address(presaleProxy);

        // Track the presale
        presales.push(presale);
        isPresale[presale] = true;

        emit PresaleDeployed(presale, msg.sender, phases.length, config.saleType);
    }

    /*//////////////////////////////////////////////////////////////
                      POOL CREATION (CALLED BY PRESALES)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Create a bToken and pool on behalf of a presale
     * @dev Only callable by presales deployed through this factory.
     *      Routes bFactory calls through the factory so only the factory
     *      needs to be approved on Baseline.
     * @param name bToken name
     * @param symbol bToken symbol
     * @param totalSupply bToken total supply
     * @param salt Deterministic deployment salt
     * @param createParams BFactory pool creation parameters (bToken field is overwritten)
     * @param poolReserves Amount of reserve tokens to pull from the presale for the pool
     * @return bToken Address of the created bToken
     */
    function createBTokenAndPool(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        bytes32 salt,
        BFactory.CreateParams memory createParams,
        uint256 poolReserves
    ) external returns (address bToken) {
        if (!isPresale[msg.sender]) revert UnauthorizedPresale();

        // Create bToken (minted to this factory)
        bToken = bFactory.createBToken(name, symbol, totalSupply, salt);
        createParams.bToken = bToken;

        // Pull reserve tokens from the presale
        IERC20(createParams.reserve).safeTransferFrom(msg.sender, address(this), poolReserves);

        // Approve bFactory to spend reserve tokens and bTokens
        IERC20(createParams.reserve).safeIncreaseAllowance(address(bFactory), poolReserves);
        IERC20(bToken).safeIncreaseAllowance(
            address(bFactory), createParams.initialPoolBTokens + createParams.initialCollateral
        );

        // Create pool
        bFactory.createPool(createParams);

        // Send remaining bTokens (circulating supply) back to the presale
        uint256 remainingBTokens = IERC20(bToken).balanceOf(address(this));
        if (remainingBTokens > 0) {
            IERC20(bToken).safeTransfer(msg.sender, remainingBTokens);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the current implementation address
     * @return Address of the current implementation
     */
    function getImplementation() external view returns (address) {
        return presaleBeacon.implementation();
    }

    /**
     * @notice Get the beacon address
     * @return Address of the beacon contract
     */
    function getBeacon() external view returns (address) {
        return address(presaleBeacon);
    }

    /**
     * @notice Get all deployed presale contracts
     * @return Array of presale contract addresses
     */
    function getAllPresales() external view returns (address[] memory) {
        return presales;
    }

    /**
     * @notice Get the number of deployed presales
     * @return Number of deployed presales
     */
    function getPresaleCount() external view returns (uint256) {
        return presales.length;
    }

    /**
     * @notice Get the BFactory address
     * @return Address of the BFactory contract
     */
    function getBFactoryAddress() external view returns (address) {
        return address(bFactory);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setPresaleBeacon(IBeacon _presaleBeacon) internal {
        emit PresaleBeaconModified(presaleBeacon, _presaleBeacon);
        presaleBeacon = _presaleBeacon;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
