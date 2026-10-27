import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var status = "로그인이 필요합니다."
    @State private var failed = false

    var body: some View {
        VStack(spacing: 16) {
            LogoMark(size: 96)
            Text("Vitalog")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.teal)
                .padding(.bottom, 12)

            TextField("이메일", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .themedField()
            SecureField("비밀번호", text: $password)
                .textContentType(.password)
                .themedField()
            Button("로그인") {
                Task { await signIn() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isBusy || email.isEmpty || password.isEmpty)
            .padding(.top, 4)

            Text(status)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(failed ? Theme.alert : Theme.teal.opacity(0.7))
        }
        .padding(24)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }

    private func signIn() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await supabase.auth.signIn(email: email, password: password)
            password = ""
            failed = false
        } catch {
            status = "로그인 실패: \(error.localizedDescription)"
            failed = true
        }
    }
}

#Preview {
    LoginView()
}
