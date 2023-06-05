// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

error AlreadyAdded();
error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 _selector);
error CannotAddSelectorsToZeroAddress(bytes4[] _selectors);
error CannotRemoveFunctionThatDoesNotExist(bytes4 _selector);
error CannotRemoveImmutableFunction(bytes4 _selector);
error CannotReplaceFunctionsFromFacetWithZeroAddress(bytes4[] _selectors);
error CannotReplaceFunctionThatDoesNotExists(bytes4 _selector);
error CannotReplaceFunctionWithTheSameFunctionFromTheSameFacet(bytes4 _selector);
error CannotReplaceImmutableFunction(bytes4 _selector);
error ContractHasNoCode();
error FunctionNotFound(bytes4 _functionSelector);
error IncorrectFacetCutAction(uint8 _action);
error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);
error InvalidChainlinkRate();
error InvalidNegativeFees();
error InvalidOracleType();
error InvalidParam();
error InvalidParams();
error InvalidSwap();
error InvalidTokens();
error NoSelectorsProvidedForFacetForCut(address _facetAddress);
error NotAllowed();
error NotCollateral();
error NotGovernor();
error NotGovernorOrGuardian();
error NotTrusted();
error NotWhitelisted();
error OneInchSwapFailed();
error Paused();
error RemoveFacetAddressMustBeZeroAddress(address _facetAddress);
error TooBigAmountIn();
error TooLate();
error TooSmallAmountOut();
error ZeroAddress();
error ZeroAmount();
