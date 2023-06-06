// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import { IERC20 } from "oz/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "oz/token/ERC20/extensions/IERC20Metadata.sol";
//solhint-disable
import { console } from "forge-std/console.sol";

import { AggregatorV3Interface } from "interfaces/external/chainlink/AggregatorV3Interface.sol";
import { ITransmuter } from "interfaces/ITransmuter.sol";
import "contracts/utils/Constants.sol";

import { Fixture } from "../../Fixture.sol";

contract BaseActor is Fixture {
    uint256 internal _maxAmountWithoutDecimals = 10 ** 15;
    // making this value smaller worsen rounding and make test harder to pass.
    // Trade off between bullet proof against all oracles and all interactions
    uint256 internal _minOracleValue = 10 ** 3; // 10**(-6)
    uint256 internal _minWallet = 10 ** 18; // in base 18
    uint256 internal _maxWallet = 10 ** (18 + 12); // in base 18
    int64 internal _minBurnFee = -int64(int256(BASE_9 / 2));

    mapping(bytes32 => uint256) public calls;
    address[] public actors;
    address internal _currentActor;

    ITransmuter internal _transmuter;
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
        uint256 nbrActor,
        string memory actorType,
        ITransmuter transmuter,
        address[] memory collaterals,
        AggregatorV3Interface[] memory oracles
    ) {
        for (uint256 i; i < nbrActor; ++i) {
            address actor = address(uint160(uint256(keccak256(abi.encodePacked("actor", actorType, i)))));
            actors.push(actor);
        }
        _transmuter = transmuter;
        _collaterals = collaterals;
        _oracles = oracles;
        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[0]).decimals());
        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[1]).decimals());
        _maxTokenAmount.push(_maxAmountWithoutDecimals * 10 ** IERC20Metadata(_collaterals[2]).decimals());
    }
}
