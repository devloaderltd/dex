// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ProofRegistry
 * @notice Registry for associating off-chain documents/proofs with an asset identifier.
 * @dev Stores an array of Document structs per assetId. Only owner can add in this version.
 */


contract ProofRegistry is Ownable {

    /// @notice Document record stored for an asset.

    struct Document {

        /// @notice Document type label (e.g., 'KYC', 'Deed', 'Audit').
        string docType;

        /// @notice URI to the document (IPFS or HTTPS).
        string uri;

        /// @notice Hash of the document content for integrity verification.
        bytes32 hash;
        
        /// @notice Timestamp when the record was created.
        uint256 createdAt;
    }

    /// @dev Internal mapping of documents per assetId.
    mapping(bytes32 => Document[]) private _docs;

    /// @notice Emitted when a new document is added for an asset.
    event DocumentAdded(bytes32 indexed assetId, uint256 index, string docType, string uri);

    /**
     * @notice Add a new document record for an asset.
     * @param assetId Asset identifier (e.g., a hash of an off-chain ID).
     * @param docType Document type label.
     * @param uri Document URI (IPFS/HTTPS).
     * @param hash Document content hash.
     * @dev Only callable by the owner.
     */
    function addDocument(
        bytes32 assetId,
        string calldata docType,
        string calldata uri,
        bytes32 hash
    ) external onlyOwner {
        _docs[assetId].push(
            Document({
                docType: docType,
                uri: uri,
                hash: hash,
                createdAt: block.timestamp
            })
        );
        emit DocumentAdded(assetId, _docs[assetId].length - 1, docType, uri);
    }

    /**
     * @notice Get all documents for an asset.
     * @param assetId Asset identifier.
     */
    function getDocuments(bytes32 assetId) external view returns (Document[] memory) {
        return _docs[assetId];
    }
}
