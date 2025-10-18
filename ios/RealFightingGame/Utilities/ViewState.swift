enum ViewState<Data> {
    case idle
    case loading
    case success(Data)
    case empty
    case failure(Error)

    var data: Data? {
        if case let .success(value) = self {
            return value
        }
        return nil
    }

    var error: Error? {
        if case let .failure(error) = self {
            return error
        }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
