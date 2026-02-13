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
    @State private var joinRoomCode = ""
    @State private var usernameInput = ListenTogetherClient.persistedUsername
    @State private var copiedRoomCode = false

    private var canCreateRoom: Bool {
        !usernameInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canJoinRoom: Bool {
        !usernameInput.trimmingCharacters(in: .whitespaces).isEmpty &&
        !joinRoomCode.trimmingCharacters(in: .whitespaces).isEmpty
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
    }

    // MARK: - Connected

    private var connectedContent: some View {
        VStack(spacing: 20) {
            // Status bar
            statusBar
                .padding(.top, 8)

            // Room code card
            roomCodeCard

            // Now Playing
            nowPlayingCard

            // Listeners
            listenersCard

            // Join requests (host)
            if sharePlayManager.isHost && !sharePlayManager.pendingJoinRequests.isEmpty {
                joinRequestsCard
            }

            // Suggestions (host)
            if sharePlayManager.isHost && !sharePlayManager.pendingSuggestions.isEmpty {
                suggestionsCard
            }

            // Error
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
        .padding(.vertical)
    }

    // MARK: - Disconnected

    private var disconnectedContent: some View {
        VStack(spacing: 0) {
            // Hero
            VStack(spacing: 16) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 52, weight: .thin))
                    .foregroundStyle(.cyan)
                    .symbolEffect(.pulse.byLayer)
                    .padding(.top, 48)

                Text("Listen with friends across platforms")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 32)

            // Form
            VStack(spacing: 24) {
                // Username field
                VStack(alignment: .leading, spacing: 8) {
                    Text("USERNAME")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.5)

                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)

                        TextField("Your display name", text: $usernameInput)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.07))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    }
                }
                .padding(.horizontal)

                // Create Room
                Button {
                    guard canCreateRoom else { return }
                    sharePlayManager.createRoom(username: usernameInput.trimmingCharacters(in: .whitespaces))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("Create Room")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background {
                        Capsule().fill(.cyan)
                    }
                }
                .padding(.horizontal)
                .disabled(!canCreateRoom)
                .opacity(canCreateRoom ? 1.0 : 0.4)

                // Divider
                HStack(spacing: 16) {
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)
                    Text("or join a room")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(white: 0.45))
                        .fixedSize()
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)
                }
                .padding(.horizontal)

                // Room Code field + Join
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "number")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        TextField("Room Code", text: $joinRoomCode)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .onChange(of: joinRoomCode) { _, newValue in
                                let uppercased = newValue.uppercased()
                                if uppercased != newValue {
                                    joinRoomCode = uppercased
                                }
                            }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.07))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.white.opacity(0.06), lineWidth: 1)
                    }
                    .padding(.horizontal)

                    Button {
                        let trimmedUsername = usernameInput.trimmingCharacters(in: .whitespaces)
                        let trimmedCode = joinRoomCode.trimmingCharacters(in: .whitespaces)
                        guard !trimmedUsername.isEmpty, !trimmedCode.isEmpty else { return }
                        sharePlayManager.joinRoom(code: trimmedCode, username: trimmedUsername)
                    } label: {
                        Label("Join Room", systemImage: "person.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(.horizontal)
                    .disabled(!canJoinRoom)
                    .opacity(canJoinRoom ? 1.0 : 0.4)

                    if !canJoinRoom && !joinRoomCode.isEmpty {
                        Text("Enter a username to join")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

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

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(sharePlayManager.connectionStatus.rawValue)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(sharePlayManager.isHost ? "Host" : "Guest")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(sharePlayManager.isHost ? .cyan : .green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    Capsule()
                        .fill((sharePlayManager.isHost ? Color.cyan : Color.green).opacity(0.15))
                }
        }
        .padding(.horizontal)
    }

    private var statusColor: Color {
        switch sharePlayManager.connectionStatus {
        case .connected: return .green
        case .connecting, .waitingApproval, .reconnecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    // MARK: - Room Code Card

    private var roomCodeCard: some View {
        Button {
            if let code = sharePlayManager.roomCode {
                UIPasteboard.general.string = code
                copiedRoomCode = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedRoomCode = false
                }
            }
        } label: {
            VStack(spacing: 10) {
                Text("ROOM CODE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Text(sharePlayManager.roomCode ?? "---")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .tracking(6)

                HStack(spacing: 6) {
                    Image(systemName: copiedRoomCode ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                    Text(copiedRoomCode ? "Copied!" : "Tap to copy")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(copiedRoomCode ? .green : .cyan)
                .animation(.easeInOut(duration: 0.2), value: copiedRoomCode)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Now Playing Card

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NOW PLAYING")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal)

            if let song = audioPlayer.currentSong {
                HStack(spacing: 14) {
                    CachedAsyncImagePhase(url: URL(string: song.thumbnailUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white.opacity(0.08))
                                .overlay {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.title)
                            .font(.system(size: 15, weight: .semibold))
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
                            .foregroundStyle(.cyan)
                            .symbolEffect(.variableColor.iterative)
                    }
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.06))
                }
                .padding(.horizontal)
            } else {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                    Text("Nothing playing")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.06))
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Listeners Card

    private var listenersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LISTENERS \(sharePlayManager.participantCount)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(sharePlayManager.connectedUsers.enumerated()), id: \.element.id) { index, user in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(user.isHost ? .cyan.opacity(0.15) : .white.opacity(0.08))
                                .frame(width: 36, height: 36)

                            Text(String(user.username.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(user.isHost ? .cyan : .white)
                        }

                        Text(user.username)
                            .font(.system(size: 15, weight: .medium))

                        if user.userId == sharePlayManager.userId {
                            Text("You")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if user.isHost {
                            Text("Host")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.cyan.opacity(0.15)))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if index < sharePlayManager.connectedUsers.count - 1 {
                        Divider()
                            .padding(.leading, 62)
                            .opacity(0.15)
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.06))
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Join Requests (Host)

    private var joinRequestsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("JOIN REQUESTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Text("\(sharePlayManager.pendingJoinRequests.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.orange.opacity(0.15)))
            }
            .padding(.horizontal)

            VStack(spacing: 0) {
                ForEach(Array(sharePlayManager.pendingJoinRequests.enumerated()), id: \.element.id) { index, request in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.orange.opacity(0.15))
                                .frame(width: 36, height: 36)

                            Text(String(request.username.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.orange)
                        }

                        Text(request.username)
                            .font(.system(size: 15, weight: .medium))

                        Spacer()

                        Button {
                            sharePlayManager.rejectJoin(userId: request.userId)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(.white.opacity(0.08)))
                        }

                        Button {
                            sharePlayManager.approveJoin(userId: request.userId)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
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
                    .fill(.white.opacity(0.06))
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Suggestions (Host)

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUGGESTIONS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
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
                                    .fill(.white.opacity(0.08))
                                    .overlay {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(.white.opacity(0.08)))
                        }

                        Button {
                            sharePlayManager.acceptSuggestion(suggestion)
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
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
                    .fill(.white.opacity(0.06))
            }
            .padding(.horizontal)
        }
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
