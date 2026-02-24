//
//  AddCloudFolderSheet.swift
//  Wavify
//
//  Sheet for adding a Google Drive folder connection
//

import SwiftUI

struct AddCloudFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cloudManager = CloudLibraryManager.shared

    @State private var folderURL: String = ""
    @State private var folderName: String = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Add Drive Folder")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Paste a Google Drive folder link to sync its audio files")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 16)

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Folder URL")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("https://drive.google.com/drive/folders/...", text: $folderURL)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Display Name (optional)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("My Music", text: $folderName)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal)

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Button {
                    Task { await addFolder() }
                } label: {
                    HStack(spacing: 8) {
                        if isAdding {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isAdding ? "Syncing..." : "Add & Sync")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.horizontal)
                .disabled(folderURL.isEmpty || isAdding)
                .opacity(folderURL.isEmpty ? 0.5 : 1.0)

                Spacer()
            }
            .background(
                LinearGradient(
                    stops: [
                        .init(color: Color.brandGradientTop, location: 0),
                        .init(color: Color.brandBackground, location: 0.45)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Add Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func addFolder() async {
        isAdding = true
        errorMessage = nil

        do {
            try await cloudManager.addDriveFolder(
                url: folderURL,
                name: folderName.isEmpty ? nil : folderName
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isAdding = false
        }
    }
}
