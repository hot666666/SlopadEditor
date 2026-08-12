import SlopadCoreModel

// MARK: - Command Abort

extension EditorModel {
    func requireDocumentMutationSuccess(
        _ result: Result<Void, DocumentMutationResult.Failure>
    ) throws(EditorCommandAbort) {
        switch result {
        case .success:
            return

        case .failure:
            throw .abort
        }
    }
}
