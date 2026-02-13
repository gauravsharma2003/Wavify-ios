//
//  ListenTogetherView.swift
//  Wavify
//
//  Room-based WebSocket UI for synchronized listening via Metrolist relay.
//

import SwiftUI

struct ListenTogetherView: View {
    @State private var sharePlayManager = SharePlayManager.shared
    @State private var audioPlayer = AudioPlayer.shared
    @State private var showSuggestSheet = false
    @State private var showJoinSheet = false
    @State private var joinRoomCode = ""
    @State private var usernameInput = ListenTogetherClient.persistedUsername
    @State private var copiedRoomCode = false
    @State private var heroIconSwapped = false

    private var hasUsername: Bool {
        !usernameInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canJoinRoom: Bool {
        hasUsername && !joinRoomCode.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static let avatarColors: [Color] = [
        .blue, .purple, .pink, .orange, .mint, .indigo, .teal
    ]

    private func avatarColor(for name: String) -> Color {
        let index = abs(name.hashValue) % Self.avatarColors.count
        return Self.avatarColors[index]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if sharePlayManager.isSessionActive {
                    connectedContent
                } else {
                    disconnectedContent
                }
            }
            .padding(.bottom, audioPlayer.currentSong != nil ? 80 : 0)
        }
        .background(Color(hex: "1A1A1A").ignoresSafeArea())
        .overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "1A1A1A").opacity(0.95), location: 0),
                    .init(color: Color(hex: "1A1A1A").opacity(0.7), location: 0.5),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 140)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
        .navigationTitle("Listen Together")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSuggestSheet) {
            SuggestSongSheet()
        }
        .sheet(isPresented: $showJoinSheet) {
            joinRoomSheet
        }
    }

    // MARK: - Connected

    private var connectedContent: some View {
        VStack(spacing: 20) {
            roomHeader

            nowPlayingCard

            // Join requests (host)
            if sharePlayManager.isHost && !sharePlayManager.pendingJoinRequests.isEmpty {
                joinRequestsCard
            }

            // Suggestions (host)
            if sharePlayManager.isHost && !sharePlayManager.pendingSuggestions.isEmpty {
                suggestionsCard
            }

            if let error = sharePlayManager.errorMessage {
                errorBanner(error)
            }

            // Actions
            VStack(spacing: 12) {
                if sharePlayManager.isGuest {
                    Button {
                        showSuggestSheet = true
                    } label: {
                        Label("Suggest a Song", systemImage: "plus.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }

                Button {
                    sharePlayManager.endSession()
                } label: {
                    Text("Leave Room")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    // MARK: - Room Header

    private var roomHeader: some View {
        VStack(spacing: 14) {
            Button {
                if let code = sharePlayManager.roomCode {
                    UIPasteboard.general.string = code
                    copiedRoomCode = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedRoomCode = false
                    }
                }
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Room")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(sharePlayManager.roomCode ?? "---")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .tracking(3)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: copiedRoomCode ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                        Text(copiedRoomCode ? "Copied" : "Copy")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(copiedRoomCode ? .green : .white.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.07)))
                    .animation(.easeInOut(duration: 0.2), value: copiedRoomCode)
                }
            }
            .buttonStyle(.plain)

            // Listeners row
            HStack(spacing: 0) {
                HStack(spacing: -8) {
                    ForEach(sharePlayManager.connectedUsers) { user in
                        ZStack {
                            Circle()
                                .fill(avatarColor(for: user.username))
                                .frame(width: 30, height: 30)

                            Text(String(user.username.prefix(1)).uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(Color(hex: "222222"), lineWidth: 2)
                        }
                    }
                }

                Text("\(sharePlayManager.participantCount) listening")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)

                    Text(sharePlayManager.isHost ? "Host" : "Joined")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.07)))
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.05))
        }
        .padding(.horizontal)
    }

    // MARK: - Now Playing Card

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Now Playing")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal)

            if let song = audioPlayer.currentSong {
                HStack(spacing: 14) {
                    CachedAsyncImagePhase(url: URL(string: song.thumbnailUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.06))
                                .overlay {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(Color(white: 0.3))
                                }
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if audioPlayer.isPlaying {
                        Image(systemName: "waveform")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.5))
                            .symbolEffect(.variableColor.iterative)
                    }
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.05))
                }
                .padding(.horizontal)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(white: 0.3))
                    Text("Nothing playing")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(white: 0.35))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.05))
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Join Requests (Host)

    private var joinRequestsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Join Requests")
                    .font(.system(size: 15, weight: .semibold))

                Text("\(sharePlayManager.pendingJoinRequests.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.orange.opacity(0.15)))
            }
            .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(sharePlayManager.pendingJoinRequests.enumerated()), id: \.element.id) { index, request in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(avatarColor(for: request.username).opacity(0.2))
                                .frame(width: 36, height: 36)

                            Text(String(request.username.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(avatarColor(for: request.username))
                        }

                        Text(request.username)
                            .font(.system(size: 15, weight: .medium))

                        Spacer()

                        Button {
                            sharePlayManager.rejectJoin(userId: request.userId)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.white.opacity(0.07)))
                        }

                        Button {
                            sharePlayManager.approveJoin(userId: request.userId)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.green))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if index < sharePlayManager.pendingJoinRequests.count - 1 {
                        Divider()
                            .padding(.leading, 62)
                            .opacity(0.15)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.05))
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Suggestions (Host)

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggestions")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(sharePlayManager.pendingSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    HStack(spacing: 12) {
                        CachedAsyncImagePhase(url: URL(string: suggestion.track.thumbnail ?? "")) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.06))
                                    .overlay {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color(white: 0.3))
                                    }
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.track.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text("from \(suggestion.suggestedBy)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            sharePlayManager.rejectSuggestion(suggestion)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.white.opacity(0.07)))
                        }

                        Button {
                            sharePlayManager.acceptSuggestion(suggestion)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.green))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if index < sharePlayManager.pendingSuggestions.count - 1 {
                        Divider()
                            .padding(.leading, 70)
                            .opacity(0.15)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.05))
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Disconnected

    private var disconnectedContent: some View {
        VStack(spacing: 0) {
            // Hero
            VStack(spacing: 14) {
                Image(systemName: heroIconSwapped ? "shareplay" : "music.note")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: 64, weight: .thin))
                    .foregroundStyle(.white)
                    .padding(.top, 48)

                Text("Listen Together")
                    .font(.system(size: 20, weight: .bold))

                Text("Create or join a room to enjoy music\ntogether with friends in real time")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 36)
            }
            .padding(.bottom, 36)
            .onAppear {
                guard !heroIconSwapped else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation {
                        heroIconSwapped = true
                    }
                }
            }

            // Username
            VStack(spacing: 24) {
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    TextField("Enter your name to get started", text: $usernameInput)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white.opacity(0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                }
                .padding(.horizontal)

                // Two buttons side by side
                HStack(spacing: 12) {
                    // Create Room — primary glass
                    Button {
                        guard hasUsername else { return }
                        sharePlayManager.createRoom(username: usernameInput.trimmingCharacters(in: .whitespaces))
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text("Create")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .disabled(!hasUsername)
                    .opacity(hasUsername ? 1.0 : 0.35)

                    // Join Room — glass
                    Button {
                        showJoinSheet = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Join")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .disabled(!hasUsername)
                    .opacity(hasUsername ? 1.0 : 0.35)
                }
                .padding(.horizontal)

                // Error
                if let error = sharePlayManager.errorMessage {
                    errorBanner(error)
                }

                // Connection status (only when connecting/waiting)
                if sharePlayManager.connectionStatus == .connecting ||
                   sharePlayManager.connectionStatus == .waitingApproval {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)

                        Text(sharePlayManager.connectionStatus.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - Join Room Sheet

    private var joinRoomSheet: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundStyle(.white.opacity(0.5))

                Text("Join a Room")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Enter the room code shared by the host")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Room code input
            HStack(spacing: 12) {
                Image(systemName: "number")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Room Code", text: $joinRoomCode)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .onChange(of: joinRoomCode) { _, newValue in
                        let uppercased = newValue.uppercased()
                        if uppercased != newValue {
                            joinRoomCode = uppercased
                        }
                    }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            }
            .padding(.horizontal, 24)

            Spacer()

            // Join button
            Button {
                let trimmedCode = joinRoomCode.trimmingCharacters(in: .whitespaces)
                let trimmedUsername = usernameInput.trimmingCharacters(in: .whitespaces)
                guard !trimmedCode.isEmpty, !trimmedUsername.isEmpty else { return }
                showJoinSheet = false
                sharePlayManager.joinRoom(code: trimmedCode, username: trimmedUsername)
            } label: {
                Text("Join")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.horizontal, 24)
            .disabled(!canJoinRoom)
            .opacity(canJoinRoom ? 1.0 : 0.35)
            .padding(.bottom, 16)
        }
        .background(Color(white: 0.06).ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red.opacity(0.9))
                .lineLimit(2)

            Spacer()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.red.opacity(0.1))
        }
        .padding(.horizontal)
    }
}
