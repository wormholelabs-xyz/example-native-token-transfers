// SPDX-License-Identifier: Apache 2

pragma solidity >=0.8.8 <0.9.0;

import "./NttManagerHelpers.sol";
import "../mocks/DummyTransceiver.sol";
import "../../src/mocks/DummyToken.sol";
import "../../src/NttManager/NttManager.sol";
import "../../src/libraries/TrimmedAmount.sol";

library TransceiverHelpersLib {
    using TrimmedAmountLib for TrimmedAmount;

    // 0x99'E''T''T'
    bytes4 constant TEST_TRANSCEIVER_PAYLOAD_PREFIX = 0x99455454;
    uint16 constant SENDING_CHAIN_ID = 1;

    function setup_transceivers(
        NttManager nttManager,
        uint16 peerChainId
    ) internal returns (DummyTransceiver, DummyTransceiver) {
        DummyTransceiver e1 =
            new DummyTransceiver(nttManager.chainId(), address(nttManager.router()));
        DummyTransceiver e2 =
            new DummyTransceiver(nttManager.chainId(), address(nttManager.router()));
        nttManager.setTransceiver(address(e1));
        nttManager.enableSendTransceiver(peerChainId, address(e1));
        nttManager.enableRecvTransceiver(peerChainId, address(e1));
        nttManager.setTransceiver(address(e2));
        nttManager.enableSendTransceiver(peerChainId, address(e2));
        nttManager.enableRecvTransceiver(peerChainId, address(e2));
        nttManager.setThreshold(2);
        return (e1, e2);
    }

    function attestTransceiversHelper(
        address to,
        bytes32 id,
        uint16 toChain,
        NttManager nttManager,
        NttManager recipientNttManager,
        TrimmedAmount amount,
        TrimmedAmount inboundLimit,
        DummyTransceiver[] memory transceivers
    )
        internal
        returns (
            TransceiverStructs.NttManagerMessage memory m,
            TransceiverStructs.TransceiverMessage memory em
        )
    {
        m = buildNttManagerMessage(to, id, toChain, nttManager, amount);
        bytes memory encodedM = TransceiverStructs.encodeNttManagerMessage(m);

        prepTokenReceive(nttManager, recipientNttManager, amount, inboundLimit);

        // bytes memory encodedEm;
        // (em, encodedEm) = TransceiverStructs.buildAndEncodeTransceiverMessage(
        //     TEST_TRANSCEIVER_PAYLOAD_PREFIX,
        //     toWormholeFormat(address(nttManager)),
        //     toWormholeFormat(address(recipientNttManager)),
        //     encodedM,
        //     new bytes(0)
        // );

        DummyTransceiver.Message memory rmsg = DummyTransceiver.Message({
            srcChain: nttManager.chainId(),
            srcAddr: UniversalAddressLibrary.fromAddress(address(nttManager)),
            sequence: 0,
            dstChain: recipientNttManager.chainId(),
            dstAddr: UniversalAddressLibrary.fromAddress(address(recipientNttManager)),
            payloadHash: keccak256(encodedM),
            refundAddr: address(0)
        });

        for (uint256 i; i < transceivers.length; i++) {
            DummyTransceiver e = transceivers[i];

            // Attest the message.
            e.receiveMessage(rmsg);
        }

        // Execute the message.
        recipientNttManager.executeMsg(
            nttManager.chainId(),
            UniversalAddressLibrary.fromAddress(address(nttManager)),
            0,
            encodedM
        );
    }

    function buildNttManagerMessage(
        address to,
        bytes32 id,
        uint16 toChain,
        NttManager nttManager,
        TrimmedAmount amount
    ) internal view returns (TransceiverStructs.NttManagerMessage memory) {
        DummyToken token = DummyToken(nttManager.token());

        return TransceiverStructs.NttManagerMessage(
            id,
            bytes32(0),
            TransceiverStructs.encodeNativeTokenTransfer(
                TransceiverStructs.NativeTokenTransfer({
                    amount: amount,
                    sourceToken: toWormholeFormat(address(token)),
                    to: toWormholeFormat(to),
                    toChain: toChain
                })
            )
        );
    }

    function prepTokenReceive(
        NttManager nttManager,
        NttManager recipientNttManager,
        TrimmedAmount amount,
        TrimmedAmount inboundLimit
    ) internal {
        DummyToken token = DummyToken(nttManager.token());
        token.mintDummy(address(recipientNttManager), amount.untrim(token.decimals()));
        NttManagerHelpersLib.setConfigs(
            inboundLimit, nttManager, recipientNttManager, token.decimals()
        );
    }

    function buildTransceiverMessageWithNttManagerPayload(
        bytes32 id,
        bytes32 sender,
        bytes32 sourceNttManager,
        bytes32 recipientNttManager,
        bytes memory payload
    ) internal pure returns (TransceiverStructs.NttManagerMessage memory, bytes memory) {
        TransceiverStructs.NttManagerMessage memory m =
            TransceiverStructs.NttManagerMessage(id, sender, payload);
        bytes memory nttManagerMessage = TransceiverStructs.encodeNttManagerMessage(m);
        bytes memory transceiverMessage;
        (, transceiverMessage) = TransceiverStructs.buildAndEncodeTransceiverMessage(
            TEST_TRANSCEIVER_PAYLOAD_PREFIX,
            sourceNttManager,
            recipientNttManager,
            nttManagerMessage,
            new bytes(0)
        );
        return (m, transceiverMessage);
    }
}
