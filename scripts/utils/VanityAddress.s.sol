// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./Utils.s.sol";
import "stringutils/strings.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { console } from "forge-std/console.sol";
import "../Constants.s.sol";

contract VanityAddress is Utils {
    using stdJson for string;

    function _findDeploymentAddress(
        bytes32 salt,
        bytes memory initCode
    ) internal pure returns (address deploymentAddress) {
        deploymentAddress = address(
            uint160( // downcast to match the address type.
                uint256( // convert to uint to truncate upper digits.
                    keccak256( // compute the CREATE2 hash using 4 inputs.
                        abi.encodePacked( // pack all inputs to the hash together.
                            hex"ff", // start with 0xff to distinguish from RLP.
                            IMMUTABLE_CREATE2_FACTORY_ADDRESS, // this contract will be the caller.
                            salt, // pass in the supplied salt value.
                            keccak256(abi.encodePacked(initCode)) // pass in the hash of initialization code.
                        )
                    )
                )
            )
        );
    }

    function run() external {
        // Make sure that the initCode has been obtained through a via-IR compilation, or through the exact same setup as the deployment setup
        bytes
            memory initCode = hex"60406080815262000cdb80380380620000188162000364565b9283398101906060818303126200035f576200003481620003a0565b9160209262000045848401620003a0565b8584015190936001600160401b0391908282116200035f57019280601f850112156200035f57835193620000836200007d86620003b5565b62000364565b94808652878601928882840101116200035f578288620000a49301620003d1565b823b1562000305577f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc80546001600160a01b03199081166001600160a01b0386811691821790935590959194600093909290917fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b8580a2805115801590620002fd575b620001f5575b50505050507fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103937f7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f86865493815196818616885216958684820152a18315620001a3575016179055516108869081620004558239f35b60849086519062461bcd60e51b82526004820152602660248201527f455243313936373a206e65772061646d696e20697320746865207a65726f206160448201526564647265737360d01b6064820152fd5b8951946060860190811186821017620002e9578a52602785527f416464726573733a206c6f772d6c6576656c2064656c65676174652063616c6c89860152660819985a5b195960ca1b8a860152823b156200029657928092819262000280969551915af43d156200028c573d620002706200007d82620003b5565b9081528092893d92013e620003f6565b5038808080806200012d565b60609150620003f6565b895162461bcd60e51b8152600481018a9052602660248201527f416464726573733a2064656c65676174652063616c6c20746f206e6f6e2d636f6044820152651b9d1c9858dd60d21b6064820152608490fd5b634e487b7160e01b85526041600452602485fd5b508362000127565b865162461bcd60e51b815260048101879052602d60248201527f455243313936373a206e657720696d706c656d656e746174696f6e206973206e60448201526c1bdd08184818dbdb9d1c9858dd609a1b6064820152608490fd5b600080fd5b6040519190601f01601f191682016001600160401b038111838210176200038a57604052565b634e487b7160e01b600052604160045260246000fd5b51906001600160a01b03821682036200035f57565b6001600160401b0381116200038a57601f01601f191660200190565b60005b838110620003e55750506000910152565b8181015183820152602001620003d4565b9091901562000403575090565b815115620004145750805190602001fd5b6044604051809262461bcd60e51b825260206004830152620004468151809281602486015260208686019101620003d1565b601f01601f19168101030190fdfe60806040526004361015610019575b3661037c575b61037c565b6000803560e01c9081633659cfe61461006c575080634f1ef286146100675780635c60da1b146100625780638f2839701461005d5763f851a4400361000e57610326565b610212565b61019e565b6100ef565b346100d15760203660031901126100d1576100856100d4565b6001600160a01b037fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d610354163314600014610014576100ce906100c56104af565b90838252610516565b80f35b80fd5b600435906001600160a01b03821682036100ea57565b600080fd5b60403660031901126100ea576101036100d4565b60243567ffffffffffffffff918282116100ea57366023830112156100ea5781600401359283116100ea5736602484840101116100ea576001600160a01b037fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61035416331460001461001457600060208480602461018a61018561019c996104fa565b6104d4565b96828852018387013784010152610624565b005b346100ea5760003660031901126100ea576001600160a01b03807fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d610354163314600014610014577f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc5460405191168152602090f35b346100ea5760203660031901126100ea5761022b6100d4565b6001600160a01b03907fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d610391808354163314600014610014577f7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f604084549281519481851686521693846020820152a181156102bc5773ffffffffffffffffffffffffffffffffffffffff1916179055005b608460405162461bcd60e51b815260206004820152602660248201527f455243313936373a206e65772061646d696e20697320746865207a65726f206160448201527f64647265737300000000000000000000000000000000000000000000000000006064820152fd5b346100ea5760003660031901126100ea576001600160a01b037fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d61039080825416331460001461001457905460405191168152602090f35b6001600160a01b03807fb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103541633146103f0577f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc54166000808092368280378136915af43d82803e156103ec573d90f35b3d90fd5b60a460405162461bcd60e51b815260206004820152604260248201527f5472616e73706172656e745570677261646561626c6550726f78793a2061646d60448201527f696e2063616e6e6f742066616c6c6261636b20746f2070726f7879207461726760648201527f65740000000000000000000000000000000000000000000000000000000000006084820152fd5b7f4e487b7100000000000000000000000000000000000000000000000000000000600052604160045260246000fd5b604051906020820182811067ffffffffffffffff8211176104cf57604052565b610480565b6040519190601f01601f1916820167ffffffffffffffff8111838210176104cf57604052565b67ffffffffffffffff81116104cf57601f01601f191660200190565b803b156105ba576001600160a01b0381167f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc8173ffffffffffffffffffffffffffffffffffffffff198254161790557fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b600080a28151158015906105b2575b61059d575050565b6105af916105a96106b2565b91610722565b50565b506000610595565b608460405162461bcd60e51b815260206004820152602d60248201527f455243313936373a206e657720696d706c656d656e746174696f6e206973206e60448201527f6f74206120636f6e7472616374000000000000000000000000000000000000006064820152fd5b803b156105ba576001600160a01b0381167f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc8173ffffffffffffffffffffffffffffffffffffffff198254161790557fbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b600080a28151158015906106aa5761059d575050565b506001610595565b604051906060820182811067ffffffffffffffff8211176104cf57604052602782527f206661696c6564000000000000000000000000000000000000000000000000006040837f416464726573733a206c6f772d6c6576656c2064656c65676174652063616c6c60208201520152565b9190823b1561076b576000816107609460208394519201905af43d15610763573d90610750610185836104fa565b9182523d6000602084013e6107d5565b90565b6060906107d5565b608460405162461bcd60e51b815260206004820152602660248201527f416464726573733a2064656c65676174652063616c6c20746f206e6f6e2d636f60448201527f6e747261637400000000000000000000000000000000000000000000000000006064820152fd5b909190156107e1575090565b8151156107f15750805190602001fd5b6040519062461bcd60e51b82528160208060048301528251908160248401526000935b828510610837575050604492506000838284010152601f80199101168101030190fd5b848101820151868601604401529381019385935061081456fea2646970667358221220cd51d87f687e65d41171d5f157313805c8c9f1c12984f1d6b0d726a20f3df98e64736f6c634300081300330000000000000000000000000000000000ffe8b47b3e2130213b802212439497000000000000000000000000fda462548ce04282f4b6d6619823a7c64fdc018500000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000000";
        // Deploy diamond
        string memory json = vm.readFile(JSON_VANITY_PATH);
        uint256 initInt = json.readUint(string.concat("$.", "init"));
        uint256 i = initInt;
        address computedAddress;
        bool found = false;
        while (!found && i - initInt < 3000000) {
            computedAddress = _findDeploymentAddress(
                bytes32(abi.encodePacked(DEPLOYER, abi.encodePacked(uint96(i)))),
                initCode
            );
            if (uint24(uint160(bytes20(computedAddress)) >> 136) == uint24(0x004626)) {
                found = true;
                break;
            }
            i = i + 1;
        }

        console.log("found ", found);
        console.log("i ", i);
        console.logBytes32(bytes32(abi.encodePacked(DEPLOYER, abi.encodePacked(uint96(i)))));
        console.log("computedAddress ", computedAddress);
    }
}