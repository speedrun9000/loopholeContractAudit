// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBController {
    function setReserveApproval(address _reserve, bool _approved) external;
    function setApprovedCreditDeployer(address _user, bool _approved) external;
    function setFeeRecipient(address _bToken, address _recipient) external;
}
