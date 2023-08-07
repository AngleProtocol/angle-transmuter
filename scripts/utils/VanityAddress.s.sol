// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import { Utils } from "./Utils.s.sol";
import "stringutils/strings.sol";
import { console } from "forge-std/console.sol";
import "../Constants.s.sol";

contract VanityAddress is Utils {
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
        bytes
            memory initCode = "0x6080604052610de5803803806100148161021e565b928339606090818382810103126100da578251916001600160401b0383116100da57818401601f8486010112156100da578284015161005a61005582610243565b61021e565b93602085838152019084870160208460051b838a010101116100da57602081880101915b60208460051b838a01010183106100df5787878761009e6020840161025a565b6040840151939091906001600160401b0385116100da576100cc946100c692820191016102ac565b9161049e565b60405160f19081610cb48239f35b600080fd5b82516001600160401b0381116100da578289010185601f1982898c010301126100da5761010a6101db565b906101176020820161025a565b8252604081015160038110156100da57602083015280870151906001600160401b0382116100da5701878a01603f820112156100da5760208101519061015f61005583610243565b91602083828152018a8d0160408360051b850101116100da5760408301905b60408360051b85010182106101a45750505050604082015281526020928301920161007e565b81516001600160e01b0319811681036100da5781526020918201910161017e565b634e487b7160e01b600052604160045260246000fd5b60405190606082016001600160401b038111838210176101fa57604052565b6101c5565b60408051919082016001600160401b038111838210176101fa57604052565b6040519190601f01601f191682016001600160401b038111838210176101fa57604052565b6001600160401b0381116101fa5760051b60200190565b51906001600160a01b03821682036100da57565b6001600160401b0381116101fa57601f01601f191660200190565b60005b83811061029c5750506000910152565b818101518382015260200161028c565b81601f820112156100da5780516102c56100558261026e565b92818452602082840101116100da576102e49160208085019101610289565b90565b634e487b7160e01b600052601160045260246000fd5b600019811461030c5760010190565b6102e7565b634e487b7160e01b600052603260045260246000fd5b805182101561033b5760209160051b010190565b610311565b6003111561034a57565b634e487b7160e01b600052602160045260246000fd5b51600381101561034a5790565b90815180825260208080930193019160005b82811061038d575050505090565b83516001600160e01b0319168552938101939281019260010161037f565b906020916103c481518092818552858086019101610289565b601f01601f1916010190565b93929091936060928382019380835281518095526080830160808660051b85010195602080940192600080915b83831061042f575050505050506102e494956104229183019060018060a01b03169052565b60408184039101526103ab565b909192939498607f1988820301865289519060018060a01b03825116815287820151600381101561048a5761047c60019385848c959486809601528160408094015193820152019061036d565b9b01960194930191906103fd565b634e487b7160e01b85526021600452602485fd5b929190835160005b8181106104f05750507f8faa70878671ccd212d20771b795c50af8fd3ff6cf27f4bde57e5d4de0aeb673816104ee94956104e685604051938493846103d0565b0390a16105eb565b565b6040806104fd8389610327565b51015161051b61050d848a610327565b51516001600160a01b031690565b918151156105a65750908291610540602061053961055d968c610327565b5101610360565b61054981610340565b80610562575061055891610751565b6102fd565b6104a6565b61056b81610340565b6001810361057d5750610558916108a9565b80610589600292610340565b14610596575b50506102fd565b61059f91610a81565b388061058f565b5163e767f91f60e01b81526001600160a01b0383166004820152602490fd5b0390fd5b6001600160a01b0390911681526040602082018190526102e4929101906103ab565b906001600160a01b0382161561066e5761060482610c99565b600080825160208401855af4913d15610666573d926106256100558561026e565b9384523d6000602086013e5b1561063b57505050565b82511561064a57825160208401fd5b6105c560405192839263192105d760e01b8452600484016105c9565b606092610631565b5050565b9060206102e492818152019061036d565b8151815460209093015161ffff60a01b60a09190911b166001600160b01b03199093166001600160a01b0390911617919091179055565b90600080516020610dc5833981519152805483101561033b57600052601c60206000208360031c019260021b1690565b600080516020610dc583398151915290815491680100000000000000008310156101fa57826107219160016104ee950190556106ba565b90919063ffffffff83549160031b9260e01c831b921b1916179055565b61ffff80911690811461030c5760010190565b906001600160a01b0382161561088c57600080516020610dc58339815191525461ffff1661077e83610c99565b8151916000915b838310610793575050505050565b6107ae6107a08484610327565b516001600160e01b03191690565b6107f76107eb6107de8363ffffffff60e01b16600052600080516020610da5833981519152602052604060002090565b546001600160a01b031690565b6001600160a01b031690565b610868576108629161085761085c926108526108116101ff565b6001600160a01b038b16815261ffff851660208201526001600160e01b031983166000908152600080516020610da583398151915260205260409020610683565b6106ea565b61073e565b926102fd565b91610785565b60405163ebbf5d0760e01b81526001600160e01b0319919091166004820152602490fd5b6040516302b8da0760e21b81529081906105c59060048301610672565b6001600160a01b038116919082156109e6576108c481610c99565b81519160005b8381106108d8575050505050565b6108e56107a08284610327565b6109156107eb6107de8363ffffffff60e01b16600052600080516020610da5833981519152602052604060002090565b3081146109c4578681146109a2571561097e57906105588461095a6109799463ffffffff60e01b16600052600080516020610da5833981519152602052604060002090565b80546001600160a01b0319166001600160a01b03909216919091179055565b6108ca565b604051637479f93960e01b81526001600160e01b0319919091166004820152602490fd5b604051631ac6ce8d60e11b81526001600160e01b031983166004820152602490fd5b604051632901806d60e11b81526001600160e01b031983166004820152602490fd5b60405163cd98a96f60e01b8152806105c58460048301610672565b9061ffff610a0d6101ff565b92546001600160a01b038116845260a01c166020830152565b801561030c576000190190565b600080516020610dc583398151915280548015610a6b576000190190610a58826106ba565b63ffffffff82549160031b1b1916905555565b634e487b7160e01b600052603160045260246000fd5b600080516020610dc58339815191525491906001600160a01b038116610c765750809291925190600090815b838110610abc57505050509050565b610ac96107a08284610327565b95610afc610af78863ffffffff60e01b16600052600080516020610da5833981519152602052604060002090565b610a01565b8051909190610b13906001600160a01b03166107eb565b15610c545781513090610b2e906001600160a01b03166107eb565b14610c3257610b9460209798610b9a9493610b498894610a26565b998a91018161ffff610b5d835161ffff1690565b1603610ba2575b5050610b6e610a33565b63ffffffff60e01b16600052600080516020610da5833981519152602052604060002090565b556102fd565b949394610aad565b610c0c610be5610bc4610bb7610c2b956106ba565b90549060031b1c60e01b90565b92610bdd84610721610bd8845161ffff1690565b6106ba565b5161ffff1690565b9163ffffffff60e01b16600052600080516020610da5833981519152602052604060002090565b805461ffff60a01b191660a09290921b61ffff60a01b16919091179055565b8838610b64565b604051630df5fd6160e31b81526001600160e01b031989166004820152602490fd5b604051637a08a22d60e01b81526001600160e01b031989166004820152602490fd5b60405163d091bc8160e01b81526001600160a01b03919091166004820152602490fd5b3b15610ca157565b60405163c1df45cf60e01b8152600490fdfe60007fffffffff000000000000000000000000000000000000000000000000000000008135168082527fc8fcad8db84d3cc18b4c41d551ea0ee66dd599cde068d998e57d5e09332c131c60205273ffffffffffffffffffffffffffffffffffffffff604083205416908115608e57508180913682608037608036915af43d809260803e15608a576080f35b6080fd5b7f5416eb980000000000000000000000000000000000000000000000000000000060805260845260246080fdfea264697066735822122021360f147bbcb1600d3a729f1f1e0e140d92f6be26118f336f52913902a7ef8d64736f6c63430008130033c8fcad8db84d3cc18b4c41d551ea0ee66dd599cde068d998e57d5e09332c131cc8fcad8db84d3cc18b4c41d551ea0ee66dd599cde068d998e57d5e09332c131b0000000000000000000000000000000000000000000000000000000000000060000000000000000000000000e8c2c34599eaf8006e466398b378067db7d3c4790000000000000000000000000000000000000000000000000000000000000ce00000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000280000000000000000000000000000000000000000000000000000000000000038000000000000000000000000000000000000000000000000000000000000006c0000000000000000000000000000000000000000000000000000000000000076000000000000000000000000000000000000000000000000000000000000009200000000000000000000000000000000000000000000000000000000000000a200000000000000000000000000000000000000000000000000000000000000b6000000000000000000000000053b7d70013dec21a97f216e80eefcf45f25c29000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000011f931c1c00000000000000000000000000000000000000000000000000000000000000000000000000000000fa94cd9d711de75695693c877beca5473462cf120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000025c60da1b00000000000000000000000000000000000000000000000000000000c39aa07d0000000000000000000000000000000000000000000000000000000000000000000000000000000065ddeedf8e68f26d787b678e28af13fde0249967000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000004cdffacc60000000000000000000000000000000000000000000000000000000052ef6b2c00000000000000000000000000000000000000000000000000000000adfca15e000000000000000000000000000000000000000000000000000000007a0ed62700000000000000000000000000000000000000000000000000000000000000000000000000000000d1b575ed715e4630340bfdc4fb8a37df3383c84a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000016b4a0bdf300000000000000000000000000000000000000000000000000000000ee565a6300000000000000000000000000000000000000000000000000000000847da7be00000000000000000000000000000000000000000000000000000000eb7aac5f000000000000000000000000000000000000000000000000000000003335221000000000000000000000000000000000000000000000000000000000b718136100000000000000000000000000000000000000000000000000000000b85780bc00000000000000000000000000000000000000000000000000000000cd377c5300000000000000000000000000000000000000000000000000000000782513bd0000000000000000000000000000000000000000000000000000000094e35d9e000000000000000000000000000000000000000000000000000000004ea3e3430000000000000000000000000000000000000000000000000000000010d3d22e0000000000000000000000000000000000000000000000000000000038c269eb00000000000000000000000000000000000000000000000000000000adc9d1f7000000000000000000000000000000000000000000000000000000008db9653f000000000000000000000000000000000000000000000000000000000d1266270000000000000000000000000000000000000000000000000000000096d6487900000000000000000000000000000000000000000000000000000000fe7d0c540000000000000000000000000000000000000000000000000000000077dc342900000000000000000000000000000000000000000000000000000000f9839d8900000000000000000000000000000000000000000000000000000000a52aefd40000000000000000000000000000000000000000000000000000000099eeca4900000000000000000000000000000000000000000000000000000000000000000000000000000000770756e43b9ac742538850003791def3020211f300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000105b41934000000000000000000000000000000000000000000000000000000000000000000000000000000001f37f93c6aa7d987ae04786145d3066eab8eeb4300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000af0d2d5a800000000000000000000000000000000000000000000000000000000c1cdee7e0000000000000000000000000000000000000000000000000000000087c8ab7a000000000000000000000000000000000000000000000000000000005c3eebda000000000000000000000000000000000000000000000000000000001f0ec8ee000000000000000000000000000000000000000000000000000000000e32cb860000000000000000000000000000000000000000000000000000000081ee2deb00000000000000000000000000000000000000000000000000000000b13b0847000000000000000000000000000000000000000000000000000000001b0c7182000000000000000000000000000000000000000000000000000000007c0343a100000000000000000000000000000000000000000000000000000000000000000000000000000000dda8f002925a0dfb151c0eacb48d7136ce6a999f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000004629feb62000000000000000000000000000000000000000000000000000000004eec47b900000000000000000000000000000000000000000000000000000000a9e6a1a400000000000000000000000000000000000000000000000000000000b607d0990000000000000000000000000000000000000000000000000000000000000000000000000000000006c33a0c80c3970cbedde641c7a6419d703d93d70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000064583aea6000000000000000000000000000000000000000000000000000000009525f3ab000000000000000000000000000000000000000000000000000000003b6a1fe000000000000000000000000000000000000000000000000000000000d92c6cb200000000000000000000000000000000000000000000000000000000b92567fa00000000000000000000000000000000000000000000000000000000c10a6287000000000000000000000000000000000000000000000000000000000000000000000000000000008e669f6ef8485694196f32d568ba4ac268b9fe8f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000004d703a0cd00000000000000000000000000000000000000000000000000000000815822c1000000000000000000000000000000000000000000000000000000002e7639bc00000000000000000000000000000000000000000000000000000000fd7daaf8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000064c0c53b8b0000000000000000000000005bc6bef80da563ebf6df6d6913513fa9a7ec89be0000000000000000000000001a7e4e63778b4f12a199c062f3efdd288afcbce80000000000000000000000005d34839a3d4051f630d36e26698d53c58dd3907200000000000000000000000000000000000000000000000000000000";
        // Deploy diamond
        uint256 i = 0;
        address computedAddress;
        bool found = false;
        while (!found) {
            computedAddress = _findDeploymentAddress(
                bytes32(abi.encodePacked(DEPLOYER, abi.encodePacked(uint64(i)))),
                initCode
            );
            if (uint24(uint160(bytes20(computedAddress))) == uint24(0x002535)) {
                found = true;
                break;
            }
            i = i + 1;
            console.log(i);
        }
        console.log("FOUND");
        console.log(i);
        console.logBytes32(bytes32(abi.encodePacked(DEPLOYER, abi.encodePacked(uint64(i)))));
        console.log(computedAddress);
    }
}
