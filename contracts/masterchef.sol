// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


// Import SafeMath library
import "@openzeppelin/contracts/utils/math/SafeMath.sol";



interface IMigratorChef {
    function migrate(IERC20 token) external returns (IERC20);
}

contract Mochicum is ERC20, Ownable {

    uint256 _maxSupply;

    constructor(uint256 maxSupply_) ERC20("Mochicum", "MOCS") {
        _maxSupply = maxSupply_ * 1e18;
    }

    function maxSupply() public view returns (uint256) {
        return _maxSupply / 1e18;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(totalSupply() + amount <= _maxSupply, "Mochicum: max supply exceeded");
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        require(to != address(this), "Mochicum: invalid transfer");
    }
}

contract MasterChef is Ownable {
   using SafeMath for uint256; 
   struct UserInfo {
    uint256 amount;               // How many LP tokens the user has provided.
    uint256 rewardDebt;           // Reward debt. See explanation below.
    uint256 totalHarvested;       // Total amount of tokens harvested by the user.
    //
    // We do some fancy math here. Basically, any point in time, the amount of Mochicum
    // entitled to a user but is pending to be distributed is:
    //
    //   pending reward = (user.amount * pool.accMochicumPerShare) - user.rewardDebt
    //
    // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
    //   1. The pool's `accMochicumPerShare` (and `lastRewardBlock`) gets updated.
    //   2. User's `amount` gets updated.
    //   3. User's `rewardDebt` gets updated.
}

 struct PoolInfo {
    IERC20 lpToken;               // Address of LP token contract
    uint256 allocPoint;           // How many allocation points assigned to this pool
    uint256 lastRewardBlock;      // Last block number that reward distribution occurs
    uint256 accMochicumPerShare;  // Accumulated mochicum per share, times 1e18
    uint256 depositFeeRate;       // Deposit fee rate, in basis points
    uint256 startBlock;
    uint256 endBlock;
    uint256 lpSupply;
}


    Mochicum public mochicum;
    uint256 public mochicumPerBlock;
    uint256 public constant BONUS_MULTIPLIER = 1;
    IMigratorChef public migrator;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint = 0;
    uint256 public startBlock;
    uint256 public endBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        Mochicum _mochicum,
        uint256 _mochicumPerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) {
        mochicum = _mochicum;
        mochicumPerBlock = _mochicumPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function add(
    uint256 _allocPoint,
    IERC20 _lpToken,
    uint16 _depositFeeRate,
    bool _withUpdate,
    uint256 _startBlock,
    uint256 _endBlock
) public onlyOwner {
    require(_depositFeeRate <= 10000, "add: invalid deposit fee rate basis points");
    if (_withUpdate) {
        massUpdatePools();
    }
    uint256 lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
    totalAllocPoint = totalAllocPoint.add(_allocPoint); 
    poolInfo.push(
        PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accMochicumPerShare: 0,
            depositFeeRate: _depositFeeRate,
            startBlock: _startBlock,
            endBlock: _endBlock,
            lpSupply: 0
        })
    );
}


    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
}
function setMigrator(IMigratorChef _migrator) public onlyOwner {
    migrator = _migrator;
}

function migrate(uint256 _pid) public onlyOwner {
    require(address(migrator) != address(0), "MasterChef: no migrator");
    PoolInfo storage pool = poolInfo[_pid];
    uint256 bal = pool.lpToken.balanceOf(address(this));
    pool.lpToken.approve(address(migrator), bal);
    IERC20 newLpToken = migrator.migrate(pool.lpToken);
    require(bal == newLpToken.balanceOf(address(this)), "MasterChef: migrated balance mismatch");
    pool.lpToken = newLpToken;
}

function massUpdatePools() public {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
        updatePool(pid);
    }
}

function updatePool(uint256 _pid) public {
    PoolInfo storage pool = poolInfo[_pid];
    if (block.number <= pool.lastRewardBlock) {
        return;
    }
    uint256 lpSupply = pool.lpToken.balanceOf(address(this));
    if (lpSupply == 0) {
        pool.lastRewardBlock = block.number < endBlock ? block.number : endBlock;
        return;
    }
    uint256 lastRewardBlock = block.number < endBlock ? block.number : endBlock;
    uint256 numBlocks = lastRewardBlock - pool.lastRewardBlock;
    uint256 mochicumReward = numBlocks * mochicumPerBlock * pool.allocPoint / totalAllocPoint * BONUS_MULTIPLIER;
    mochicum.mint(address(this), mochicumReward);
    pool.accMochicumPerShare += mochicumReward * 1e18 / lpSupply;
    pool.lastRewardBlock = lastRewardBlock;
}

function _harvest(uint256 _pid, address _to) internal {
    UserInfo storage user = userInfo[_pid][_to];
    uint256 accMochicumPerShare = poolInfo[_pid].accMochicumPerShare;
    uint256 pending = user.amount * accMochicumPerShare / 1e18 - user.rewardDebt;
    if (pending > 0) {
        safeMochicumTransfer(_to, pending);
    }
    user.rewardDebt = user.amount * accMochicumPerShare / 1e18;
}

function deposit(uint256 _pid, uint256 _amount) public {
    require(block.number >= startBlock, "MasterChef: not started yet");
    require(block.number <= endBlock, "MasterChef: already ended");
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    updatePool(_pid);
    if (user.amount > 0) {
        uint256 pending = user.amount * pool.accMochicumPerShare / 1e18 - user.rewardDebt;
        if (pending > 0) {
            safeMochicumTransfer(msg.sender, pending * 99 / 100);
            safeMochicumTransfer(owner(), pending * 1 / 100);
        }
    }
    if (_amount > 0) {
         // Transfer the LP tokens from the user to the masterchef contract
        SafeERC20.safeTransferFrom(pool.lpToken, msg.sender, address(this), _amount);
        uint256 depositFee = _amount.mul(pool.depositFeeRate).div(10000);
        user.amount = user.amount + _amount - depositFee;
        user.rewardDebt = user.amount * pool.accMochicumPerShare / 1e18;
        pool.lpSupply = pool.lpSupply.add(_amount).sub(depositFee);
    if (depositFee > 0) {
        SafeERC20.safeTransfer(pool.lpToken, owner(), depositFee);  // Transfer 2% deposit fee to owner
        pool.lpSupply = pool.lpSupply.add(_amount).sub(depositFee); 
    }
    else {
        pool.lpSupply = pool.lpSupply.add(_amount);
    }

    }
    
    emit Deposit(msg.sender, _pid, _amount);
}

function withdraw(uint256 _pid, uint256 _amount) public {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.amount >= _amount, "MasterChef: insufficient balance");
    updatePool(_pid);
    _harvest(_pid, msg.sender);
    if (_amount > 0) {
    user.amount -= _amount;
    pool.lpToken.transfer(address(msg.sender), _amount);
    }
    user.rewardDebt = user.amount * pool.accMochicumPerShare / 1e18;
    emit Withdraw(msg.sender, _pid, _amount);
    }


function harvest(uint256 _pid) public {
    require(block.number > startBlock, "MasterChef: not started yet");
    require(block.number <= endBlock, "MasterChef: already ended");
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    updatePool(_pid);
      uint256 pending = user.amount * pool.accMochicumPerShare / 1e18 - user.rewardDebt;
    if (pending > 0) {
        safeMochicumTransfer(msg.sender, pending * 99 / 100);
        safeMochicumTransfer(owner(), pending * 1 / 100);
    }
    user.rewardDebt = user.amount * pool.accMochicumPerShare / 1e18;
    _harvest(_pid, msg.sender);  // Call _harvest as a regular function
}


function harvestAll() public {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
        if (userInfo[pid][msg.sender].amount > 0) {
            harvest(pid);
        }
    }
}

function safeMochicumTransfer(address _to, uint256 _amount) internal {
    uint256 mochicumBal = mochicum.balanceOf(address(this));
    if (_amount > mochicumBal) {
        mochicum.transfer(_to, mochicumBal);
    } else {
        mochicum.transfer(_to, _amount);
        }
    }
}

