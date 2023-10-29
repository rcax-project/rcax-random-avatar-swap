// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155ReceiverUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "libraries/AvatarContracts.sol";

// Users can swap their Aww/Drip/Meme/Singu and paid avatars instantly with an avatar in from the same pool.
// First swap is free, then it will cost a RCAX fee per swap.
// Half of the fee will go to the liquidity provider.
// Other half of the fees will go to the contract owner.

/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract RCAXAvatarSwap is Initializable, PausableUpgradeable, OwnableUpgradeable, ERC1155ReceiverUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct AvatarToken {
        address owner;
        address tokenAddress;
        uint256 tokenId;
    }

    address public constant RCAX_TOKEN_ADDRESS = 0x875f123220024368968d9f1aB1f3F9C2f3fd190d;
    address public constant RCAX_DEV_FUND_WALLET = 0xB5C42f30cEAE2032F22d364E33A5BaEfA1A043FF;
    string public constant AWW_DRIP_MEME_SINGU_POOL_IDENTIFIER = "awwdripmemesingu";
    string public constant GEN_1_POOL_IDENTIFIER = "gen1";
    string public constant GEN_2_POOL_IDENTIFIER = "gen2";
    string public constant GEN_3_POOL_IDENTIFIER = "gen3";
    uint256 public constant AWW_DRIP_MEME_SINGU_POOL_FEE = 20 * 10**18;
    uint256 public constant GEN_1_POOL_FEE = 80 * 10**18;
    uint256 public constant GEN_2_POOL_FEE = 40 * 10**18;
    uint256 public constant GEN_3_POOL_FEE = 20 * 10**18;

    mapping(address => bool) private _freeDemoUsed;
    mapping(address => bool) private _isLiquidityProvider;
    mapping(string => AvatarToken[]) _avatarPools;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyOwner
    override
    {}

    // Get the pool identifier for an avatar contract address
    function getPoolIdentifier(address tokenAddress) public pure returns (string memory) {
        if (AvatarContracts.isAvatarAwwDripMemeSingu(tokenAddress)) {
            return AWW_DRIP_MEME_SINGU_POOL_IDENTIFIER;
        } else if (AvatarContracts.isAvatarGen1(tokenAddress)) {
            return GEN_1_POOL_IDENTIFIER;
        } else if (AvatarContracts.isAvatarGen2(tokenAddress)) {
            return GEN_2_POOL_IDENTIFIER;
        } else if (AvatarContracts.isAvatarGen3(tokenAddress)) {
            return GEN_3_POOL_IDENTIFIER;
        } else {
            revert("RCA is not eligible for a swap");
        }
    }

    function getPoolFeeForToken(address tokenAddress) public pure returns (uint256) {
        if (AvatarContracts.isAvatarAwwDripMemeSingu(tokenAddress)) {
            return AWW_DRIP_MEME_SINGU_POOL_FEE;
        } else if (AvatarContracts.isAvatarGen1(tokenAddress)) {
            return GEN_1_POOL_FEE;
        } else if (AvatarContracts.isAvatarGen2(tokenAddress)) {
            return GEN_2_POOL_FEE;
        } else if (AvatarContracts.isAvatarGen3(tokenAddress)) {
            return GEN_3_POOL_FEE;
        } else {
            revert("RCA is not eligible for a swap");
        }
    }

    // Check if there is enough avatars in the pool
    // Perform a swap if so
    function _checkDoSwap(address initiator, AvatarToken memory initiatorAvatar) internal {
        string memory poolIdentifier = getPoolIdentifier(initiatorAvatar.tokenAddress);

        require(_avatarPools[poolIdentifier].length >= 1, "Pool size is too small for a swap");

        _performSwap(initiator, initiatorAvatar);
    }

    // Generate a pseudo-random index based on block information
    function _getRandomIndex(uint256 maxIndex) internal view returns (uint256) {
        uint256 blockValue = uint256(blockhash(block.number - 1));
        return blockValue % maxIndex;
    }

    // Send avatar to recipient
    function _sendAvatar(address recipient, address tokenAddress, uint256 tokenId) internal {
        require(IERC1155(tokenAddress).balanceOf(address(this), tokenId) == 1, "Avatar is not owned by the contract");

        try IERC1155(tokenAddress).safeTransferFrom(address(this), recipient, tokenId, 1, "") {
            // Successful transfer
        } catch (bytes memory revertReason) {
            // Handle the revert reason, e.g., by emitting an event or reverting with an error message
            revert(string(revertReason));
        }
    }

    function setLiquidityProviderStatus(bool status) external {
        require(status != _isLiquidityProvider[msg.sender], "Liquidity provider status is already set");

        _isLiquidityProvider[msg.sender] = status;
    }

    function getLiquidityProviderStatus(address wallet) external view returns (bool) {
        return _isLiquidityProvider[wallet];
    }

    function getFreeDemoUsedStatus(address wallet) external view returns (bool) {
        return _freeDemoUsed[wallet];
    }

    function withdrawAllAvatars() external {
        _withdrawAllAvatarsFromPool(AWW_DRIP_MEME_SINGU_POOL_IDENTIFIER);
        _withdrawAllAvatarsFromPool(GEN_1_POOL_IDENTIFIER);
        _withdrawAllAvatarsFromPool(GEN_2_POOL_IDENTIFIER);
        _withdrawAllAvatarsFromPool(GEN_3_POOL_IDENTIFIER);
    }

    function _withdrawAllAvatarsFromPool(string memory poolIdentifier) internal {
        AvatarToken[] memory poolAvatars = getAllAvatarsInPoolForOwner(msg.sender, poolIdentifier);

        for (uint256 i = 0; i < poolAvatars.length; i++) {
            _withdrawAvatar(poolAvatars[i]);
        }
    }

    function getAllAvatarsInPoolForOwner(address owner, string memory poolIdentifer) public view returns (AvatarToken[] memory) {
        uint256 ownedAvatarsAmount = 0;

        for (uint256 i = 0; i < _avatarPools[poolIdentifer].length; i++) {
            if (_avatarPools[poolIdentifer][i].owner == owner) {
                ownedAvatarsAmount += 1;
            }
        }

        uint256 foundOwnedAvatarsAmount = 0;
        AvatarToken[] memory ownedAvatars = new AvatarToken[](ownedAvatarsAmount);

        for (uint256 i = 0; i < _avatarPools[poolIdentifer].length; i++) {
            if (_avatarPools[poolIdentifer][i].owner == owner) {
                ownedAvatars[foundOwnedAvatarsAmount] = AvatarToken({
                owner: _avatarPools[poolIdentifer][i].owner,
                tokenAddress: _avatarPools[poolIdentifer][i].tokenAddress,
                tokenId: _avatarPools[poolIdentifer][i].tokenId
                });

                foundOwnedAvatarsAmount += 1;
            }
        }

        return ownedAvatars;
    }

    function _withdrawAvatar(AvatarToken memory avatar) internal {
        require(avatar.owner == msg.sender, "Only the owner can withdraw their avatars");

        string memory poolIdentifier = getPoolIdentifier(avatar.tokenAddress);

        bool avatarFound = false;

        // Remove the avatar from the pool
        for (uint256 i = 0; i < _avatarPools[poolIdentifier].length; i++) {
            if (_avatarPools[poolIdentifier][i].tokenAddress == avatar.tokenAddress && _avatarPools[poolIdentifier][i].tokenId == avatar.tokenId) {
                _avatarPools[poolIdentifier][i] = _avatarPools[poolIdentifier][_avatarPools[poolIdentifier].length - 1];
                avatarFound = true;
                break;
            }
        }

        require(avatarFound, "Could not find to be withdrawn avatar");

        _avatarPools[poolIdentifier].pop();

        _sendAvatar(msg.sender, avatar.tokenAddress, avatar.tokenId);
    }

    function _sendRCAXTokens(address from, address to, uint256 amount) internal {
        require(IERC20(RCAX_TOKEN_ADDRESS).balanceOf(from) >= amount, "Wallet does not have enough RCAX tokens");

        if (from != address(this)) {
            require(IERC20(RCAX_TOKEN_ADDRESS).allowance(from, address(this)) >= amount, "Contract is not allowed to spend enough tokens");
        }

        try IERC20(RCAX_TOKEN_ADDRESS).transferFrom(from, to, amount) {
            // Successful transfer
        } catch (bytes memory revertReason) {
            // Handle the revert reason, e.g., by emitting an event or reverting with an error message
            revert(string(revertReason));
        }
    }

    function _processServiceFee(address liquidityProvider, address initiator, uint256 amount) internal {
        uint256 contractOwnerFee = amount / 2;

        _sendRCAXTokens(initiator, liquidityProvider, amount - contractOwnerFee);
        _sendRCAXTokens(initiator, RCAX_DEV_FUND_WALLET, contractOwnerFee);
    }

    // Swap avatars between owners until no more swaps are available
    function _performSwap(address initiator, AvatarToken memory initiatorAvatar) internal {
        string memory poolIdentifier = getPoolIdentifier(initiatorAvatar.tokenAddress);

        uint256 randomPoolAvatarIndex = _getRandomIndex(_avatarPools[poolIdentifier].length);

        AvatarToken memory randomPoolAvatar = AvatarToken({
        owner: _avatarPools[poolIdentifier][randomPoolAvatarIndex].owner,
        tokenAddress: _avatarPools[poolIdentifier][randomPoolAvatarIndex].tokenAddress,
        tokenId: _avatarPools[poolIdentifier][randomPoolAvatarIndex].tokenId
        });

        if (!_freeDemoUsed[initiator]) {
            _freeDemoUsed[initiator] = true;
        } else {
            // todo: get dynamic service fee

            uint256 serviceFee = getPoolFeeForToken(initiatorAvatar.tokenAddress);

            _processServiceFee(randomPoolAvatar.owner, initiator, serviceFee);
        }

        initiatorAvatar.owner = randomPoolAvatar.owner;

        _avatarPools[poolIdentifier][randomPoolAvatarIndex] = initiatorAvatar;

        _sendAvatar(initiator, randomPoolAvatar.tokenAddress, randomPoolAvatar.tokenId);
    }

    function _addAvatarToPool(AvatarToken memory avatar) internal {
        string memory poolIdentifier = getPoolIdentifier(avatar.tokenAddress);
        _avatarPools[poolIdentifier].push(avatar);
    }

    function _handleReceivedAvatar(address from, address tokenAddress, uint256 tokenId) internal whenNotPaused() {
        AvatarToken memory avatar = AvatarToken ({
        owner: from,
        tokenAddress: tokenAddress,
        tokenId: tokenId
        });

        // If liquidity provider sends an RCA, add it to the pool directly
        // Else try and do a swap
        if (_isLiquidityProvider[from]) {
            _addAvatarToPool(avatar);
        } else {
            _checkDoSwap(from, avatar);
        }
    }

    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata
    ) public override returns (bytes4) {
        require(value == 1, "Value must be 1");

        _handleReceivedAvatar(from, msg.sender, id);

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata
    ) public override returns (bytes4) {
        for (uint256 i = 0; i < ids.length; i++) {
            require(values[i] == 1, "Every value must be 1");
        }

        for (uint256 i = 0; i < ids.length; i++) {
            _handleReceivedAvatar(from, msg.sender, ids[i]);
        }

        return this.onERC1155BatchReceived.selector;
    }

    function getAllAvatarsInPool(string memory poolIdentifer) external view returns (AvatarToken[] memory) {
        return _avatarPools[poolIdentifer];
    }
}
