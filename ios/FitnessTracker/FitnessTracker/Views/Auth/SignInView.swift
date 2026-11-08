import SwiftUI

struct SignInView: View {
    @StateObject private var viewModel = SignInViewModel()
    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("1%")
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(AppColor.accent)
                    Text("GYM  ·  NUTRITION")
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    Text("Build strength. Fuel progress.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.bottom, 42)

                VStack(spacing: 14) {
                    TextField("Email", text: $viewModel.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .authFieldSurface()

                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await viewModel.signIn() } }
                        .authFieldSurface()

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppColor.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await viewModel.signIn() }
                    } label: {
                        if viewModel.isSigningIn {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Sign In").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.appAccent)
                    .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty || viewModel.isSigningIn)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 54)
            .padding(.bottom, 32)
            .frame(maxWidth: 520, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

private extension View {
    func authFieldSurface() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
            }
    }
}

#Preview {
    SignInView()
}
