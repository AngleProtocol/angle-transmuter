// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
//solhint-disable

import { AggregatorV3Interface } from "interfaces/external/chainlink/AggregatorV3Interface.sol";
import { IAgToken } from "interfaces/IAgToken.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import { Test, stdMath, StdStorage, stdStorage } from "forge-std/Test.sol";
import "contracts/utils/Constants.sol";
import "contracts/utils/Errors.sol";

struct TestStorage {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 amountOut;
    uint256 amountInSplit1;
    uint256 amountOutSplit1;
    uint256 amountInSplit2;
    uint256 amountOutSplit2;
}

contract BaseActor is Test {
    address public constant sweeper = address(uint160(uint256(keccak256(abi.encodePacked("sweeper")))));
    uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
    // making this value smaller worsen rounding and make test harder to pass.
    // Trade off between bullet proof against all oracles and all interactions
    uint256 internal _minOracleValue = 10 ** 3; // 10**(-6)
    uint256 internal _minWallet = 10 ** 18; // in base 18
    uint256 internal _maxWallet = 10 ** (18 + 12); // in base 18
    int64 internal _minBurnFee = -int64(int256(BASE_9 / 2));

    mapping(bytes32 => uint256) public calls;
    address[] public actors;
    uint256 public nbrActor;
    address internal _currentActor;

    IAgToken agToken;
    ITransmuter internal _transmuter;
    ITransmuter internal _transmuterSplit;
    address[] internal _collaterals;
    AggregatorV3Interface[] internal _oracles;
    uint256[] internal _maxTokenAmount;

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        _currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    constructor(
        uint256 _nbrActor,
        string memory actorType,
        ITransmuter transmuter,
        ITransmuter transmuterSplit,
        address[] memory collaterals,
        AggregatorV3Interface[] memory oracles
    ) {
        for (uint256 i; i < _nbrActor; ++i) {
            address actor = address(uint160(uint256(keccak256(abi.encodePacked("actor", actorType, i)))));
            actors.push(actor);
        }
        nbrActor = _nbrActor;
        _transmuter = transmuter;
        _transmuterSplit = transmuterSplit;
        agToken = IAgToken(transmuter.agToken());
        _collaterals = collaterals;
        _oracles = oracles;
        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[0]).decimals());
        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[1]).decimals());
        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[2]).decimals());
    }
}
