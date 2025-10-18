import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var viewModel: AuthViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
        case fullName
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("", selection: Binding(get: { viewModel.mode }, set: { viewModel.switchMode($0) })) {
                    ForEach(AuthViewModel.Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 16) {
                    TextField("メールアドレス", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .email)
                        .textContentType(.emailAddress)
                        .submitLabel(.next)

                    if viewModel.mode == .signUp {
                        TextField("表示名", text: $viewModel.fullName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .fullName)
                            .textContentType(.name)
                            .submitLabel(.next)
                    }

                    SecureField("パスワード (8文字以上)", text: $viewModel.password)
                        .focused($focusedField, equals: .password)
                        .textContentType(.password)
                        .submitLabel(.go)
                }
                .textFieldStyle(.roundedBorder)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text(viewModel.mode.actionTitle)
                            .bold()
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isLoading)
            }
            .padding(24)
            .navigationTitle("Real Fighting Game")
            .onSubmit(handleSubmit)
        }
    }

    private func submit() {
        viewModel.submit()
        focusedField = nil
    }

    private func handleSubmit() {
        switch focusedField {
        case .email:
            focusedField = viewModel.mode == .signUp ? .fullName : .password
        case .fullName:
            focusedField = .password
        case .password, .none:
            submit()
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthViewModel())
}
