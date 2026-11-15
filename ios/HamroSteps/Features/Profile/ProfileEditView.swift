import PhotosUI
import SwiftUI

/// Me › Edit profile: photo, name, where they live and birthday, on one
/// screen. A photo change saves straight away; the rest saves with Save.
struct ProfileEditView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var city: String
    @State private var birthday: Date?
    @State private var editingBirthday = false

    @State private var pickedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var photoBusy = false
    @State private var isSaving = false
    @State private var message: String?

    private let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    init(user: AppUser?) {
        _name = State(initialValue: user?.displayName ?? "")
        _city = State(initialValue: user?.city ?? "")
        _birthday = State(initialValue: user?.birthday.flatMap { ProfileFormat.pickerDate(forBirthday: $0) })
    }

    private var canSave: Bool {
        FamilyRules.isValidName(name) && FamilyRules.isValidCity(city) && !photoBusy
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bento.gap) {
                photoTile
                    .padding(.top, 8)

                TileLabel("Your name", icon: .profile)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                TextField("Your first name", text: $name)
                    .font(.title3)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .fieldTile()

                TileLabel("Lives in", icon: .location)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                TextField("Your city, like Sydney", text: $city)
                    .font(.title3)
                    .textContentType(.addressCity)
                    .textInputAutocapitalization(.words)
                    .fieldTile()
                hint(!FamilyRules.isValidCity(city)
                     ? "Please keep it to \(FamilyRules.cityMaxLength) letters or fewer."
                     : "Your family see your city and what time it is for you.")

                TileLabel("Birthday", icon: .birthday)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
                birthdayTile
                hint("Your family see the day and month, never the year.")

                if let message { Notice(text: message) }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(.canvas)
        .tint(.accentText)
        .navigationTitle("Edit profile")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Group {
                if isSaving {
                    OrbLoader(activity: .saving)
                } else {
                    PrimaryButton(title: "Save", isEnabled: canSave, action: save)
                }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.vertical, 16)
            .background(.canvas)
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            uploadPicked(item)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { upload { ProfilePhoto.jpeg(from: image) } }
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Photo

    private var photoTile: some View {
        VStack(spacing: 16) {
            ZStack {
                Avatar(name: name, photoUrl: session.user?.photoUrl, size: 120)
                if photoBusy {
                    Circle().fill(.surface.opacity(0.7))
                    OrbLoader(activity: .addingPhoto, compact: true)
                }
            }
            .fixedSize()
            if photoBusy {
                Text("Adding your photo…")
                    .font(.subheadline)
                    .foregroundStyle(.secondaryText)
            }
            let hasPhoto = session.user?.photoUrl != nil
            VStack(spacing: 0) {
                PhotosPicker(selection: $pickedItem, matching: .images, preferredItemEncoding: .compatible) {
                    TileRow(icon: .photo, title: hasPhoto ? "Choose a new photo" : "Choose a photo",
                            showsChevron: false, isAction: true)
                }
                .buttonStyle(.plain)
                if cameraAvailable {
                    TileDivider()
                    Button {
                        showCamera = true
                    } label: {
                        TileRow(icon: .camera, title: "Take a photo", showsChevron: false, isAction: true)
                    }
                    .buttonStyle(.plain)
                }
                if session.user?.photoUrl != nil {
                    TileDivider()
                    Button(action: removePhoto) {
                        TileRow(icon: .delete, title: "Remove photo", showsChevron: false, isAction: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .disabled(photoBusy || isSaving)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Bento.padding)
        .padding(.vertical, Bento.padding)
        .bentoSurface()
    }

    private func uploadPicked(_ item: PhotosPickerItem) {
        // `upload` notes the account now, before the (possibly slow) load.
        upload {
            guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
            return ProfilePhoto.jpeg(from: data)
        }
    }

    /// `makeJPEG` reads and downscales the photo off the screen's way.
    /// The account is noted the moment the action starts, so a photo picked
    /// by one account can never be set on the next (the server checks too).
    private func upload(_ makeJPEG: @escaping @Sendable () async -> Data?) {
        guard let userId = session.user?.id else { return }
        photoBusy = true
        message = nil
        Task {
            defer { photoBusy = false }
            guard let jpeg = await Task.detached(operation: makeJPEG).value else {
                message = FamilyServiceError.invalidPhoto.message
                return
            }
            do {
                try await session.setPhoto(jpeg: jpeg, userId: userId)
            } catch {
                message = Self.message(for: error)
            }
        }
    }

    private func removePhoto() {
        guard let userId = session.user?.id else { return }
        photoBusy = true
        message = nil
        Task {
            defer { photoBusy = false }
            do {
                try await session.removePhoto(userId: userId)
            } catch {
                message = Self.message(for: error)
            }
        }
    }

    // MARK: Birthday

    @ViewBuilder
    private var birthdayTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let birthday, !editingBirthday {
                Button {
                    editingBirthday = true
                } label: {
                    TileRow(icon: .birthday, title: "\(Self.dayMonth(birthday))", value: String(localized: "Change"), showsChevron: false)
                }
                .buttonStyle(.plain)
            } else if editingBirthday {
                DatePicker(
                    "Birthday",
                    selection: Binding(get: { birthday ?? Self.defaultBirthday }, set: { birthday = $0 }),
                    in: Self.birthdayRange,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                // Gregorian like the stored "YYYY-MM-DD", whatever the phone's calendar.
                .environment(\.calendar, ProfileFormat.birthdayCalendar())
                .frame(maxWidth: .infinity)
                .onAppear { if birthday == nil { birthday = Self.defaultBirthday } }
                TileDivider()
                Button {
                    editingBirthday = false
                } label: {
                    TileRow(icon: .check, title: "Done", showsChevron: false, isAction: true)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    editingBirthday = true
                } label: {
                    TileRow(icon: .plus, title: "Add your birthday", showsChevron: false, isAction: true)
                }
                .buttonStyle(.plain)
            }
            if birthday != nil {
                TileDivider()
                Button {
                    birthday = nil
                    editingBirthday = false
                } label: {
                    TileRow(icon: .clear, title: "Remove birthday", showsChevron: false, isAction: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Bento.padding)
        .padding(.vertical, 4)
        .bentoSurface()
    }

    private static var birthdayRange: ClosedRange<Date> {
        let calendar = ProfileFormat.birthdayCalendar()
        let earliest = calendar.date(from: DateComponents(year: ProfileFormat.earliestBirthYear, month: 1, day: 1)) ?? .distantPast
        return earliest...Date.now
    }

    /// Where the wheel starts when there's no birthday yet.
    private static var defaultBirthday: Date {
        ProfileFormat.birthdayCalendar().date(from: DateComponents(year: 1970, month: 1, day: 1)) ?? .now
    }

    private static func dayMonth(_ date: Date) -> String {
        ProfileFormat.birthday(ProfileFormat.birthdayString(from: date)) ?? ""
    }

    // MARK: Save

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func save() {
        isSaving = true
        message = nil
        let profile = ProfileUpdate(
            name: name,
            city: city,
            birthday: birthday.map { ProfileFormat.birthdayString(from: $0) }
        )
        Task {
            do {
                try await session.saveProfile(profile)
                dismiss()
            } catch {
                message = Self.message(for: error)
            }
            isSaving = false
        }
    }

    /// Nothing for `CancellationError`: the account changed while saving,
    /// so there's nobody to tell.
    private static func message(for error: any Error) -> String? {
        if error is CancellationError { return nil }
        return (error as? FamilyServiceError ?? .unavailable("")).message
    }
}

#Preview {
    NavigationStack {
        ProfileEditView(user: AppUser(userId: "u", name: "Priya", needsName: false, city: "Sydney", birthday: "1990-03-12"))
    }
    .environment(SessionStore(auth: MockAuthService.preview, service: MockFamilyService.preview))
}
