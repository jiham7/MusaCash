// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//Musa.CASH
contract MusaLiquidityMining is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint256 lastRewardBlock;
        uint256 accMusaPerShare;
    }

    IERC20 public Musa;
    uint256 public MusaPerBlock = uint256(45 ether).div(10); //4.5 Musa

    PoolInfo public liquidityMining;
    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);

    function setMusaTokens(IERC20 _Musa, IERC20 _lpToken) external onlyOwner {
        require(address(Musa) == address(0) && address(liquidityMining.lpToken) == address(0), 'Tokens already set!');
        Musa = _Musa;
        liquidityMining =
            PoolInfo({
                lpToken: _lpToken,
                lastRewardBlock: 0,
                accMusaPerShare: 0
        });
    }
    
    function startMining(uint256 startBlock) external onlyOwner {
        require(liquidityMining.lastRewardBlock == 0, 'Mining already started');
        liquidityMining.lastRewardBlock = startBlock;
    }

    function pendingRewards(address _user) external view returns (uint256) {
        require(liquidityMining.lastRewardBlock > 0 && block.number >= liquidityMining.lastRewardBlock, 'Mining not yet started');
        UserInfo storage user = userInfo[_user];
        uint256 accMusaPerShare = liquidityMining.accMusaPerShare;
        uint256 lpSupply = liquidityMining.lpToken.balanceOf(address(this));
        if (block.number > liquidityMining.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number.sub(liquidityMining.lastRewardBlock);
            uint256 MusaReward = multiplier.mul(MusaPerBlock);
            accMusaPerShare = liquidityMining.accMusaPerShare.add(MusaReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accMusaPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingRewards);
    }

    function updatePool() internal {
        require(liquidityMining.lastRewardBlock > 0 && block.number >= liquidityMining.lastRewardBlock, 'Mining not yet started');
        if (block.number <= liquidityMining.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = liquidityMining.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            liquidityMining.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number.sub(liquidityMining.lastRewardBlock);
        uint256 MusaReward = multiplier.mul(MusaPerBlock);
        liquidityMining.accMusaPerShare = liquidityMining.accMusaPerShare.add(MusaReward.mul(1e12).div(lpSupply));
        liquidityMining.lastRewardBlock = block.number;
    }

    function deposit(uint256 amount) external {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(liquidityMining.accMusaPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                user.pendingRewards = user.pendingRewards.add(pending);
            }
        }
        if (amount > 0) {
            liquidityMining.lpToken.safeTransferFrom(address(msg.sender), address(this), amount);
            user.amount = user.amount.add(amount);
        }
        user.rewardDebt = user.amount.mul(liquidityMining.accMusaPerShare).div(1e12);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= amount, "Withdrawing more than you have!");
        updatePool();
        uint256 pending = user.amount.mul(liquidityMining.accMusaPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            user.pendingRewards = user.pendingRewards.add(pending);
        }
        if (amount > 0) {
            user.amount = user.amount.sub(amount);
            liquidityMining.lpToken.safeTransfer(address(msg.sender), amount);
        }
        user.rewardDebt = user.amount.mul(liquidityMining.accMusaPerShare).div(1e12);
        emit Withdraw(msg.sender, amount);
    }

    function claim() external {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        uint256 pending = user.amount.mul(liquidityMining.accMusaPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0 || user.pendingRewards > 0) {
            user.pendingRewards = user.pendingRewards.add(pending);
            uint256 claimedAmount = safeMusaTransfer(msg.sender, user.pendingRewards);
            emit Claim(msg.sender, claimedAmount);
            user.pendingRewards = user.pendingRewards.sub(claimedAmount);
        }
        user.rewardDebt = user.amount.mul(liquidityMining.accMusaPerShare).div(1e12);
    }

    function safeMusaTransfer(address to, uint256 amount) internal returns (uint256) {
        uint256 MusaBalance = Musa.balanceOf(address(this));
        if (amount > MusaBalance) {
            Musa.safeTransfer(to, MusaBalance);
            return MusaBalance;
        } else {
            Musa.safeTransfer(to, amount);
            return amount;
        }
    }
    
    function setMusaPerBlock(uint256 _MusaPerBlock) external onlyOwner {
        require(_MusaPerBlock > 0, "Musa per block should be greater than 0!");
        MusaPerBlock = _MusaPerBlock;
    }
}
