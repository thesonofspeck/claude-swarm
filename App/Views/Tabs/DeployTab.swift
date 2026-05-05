import SwiftUI
import AppCore
import PersistenceKit
import KubectlKit

/// Deploy tab — a thin UI on top of `kubectl`. Lists Deployments, Pods,
/// and Services in the project's bound context/namespace and exposes the
/// few actions we need every day (rollout restart, scale, copy logs).
///
/// The user is expected to have `kubectl` installed and `~/.kube/config`
/// already pointed at their cluster — for EKS that's
/// `aws eks update-kubeconfig --name <cluster>`. We don't try to
/// re-authenticate; we just shell out.
struct DeployTab: View {
    @Environment(AppEnvironment.self) private var env
    let project: Project?

    @State private var deployments: [K8sDeployment] = []
    @State private var pods: [K8sPod] = []
    @State private var services: [K8sService] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selectedDeploymentId: String?
    @State private var bindingSheet = false
    @State private var actionInFlight = false
    @State private var logsPod: K8sPod?

    var body: some View {
        Group {
            if let project, project.kubeContext?.isEmpty == false {
                content(project)
            } else if let project {
                emptyState(project)
            } else {
                EmptyState(
                    title: "Open a session",
                    systemImage: "shippingbox",
                    description: "Pick a project to see its Kubernetes deployments.",
                    tint: Palette.fgMuted
                )
            }
        }
        .sheet(isPresented: $bindingSheet) {
            if let project {
                KubeBindingSheet(project: project)
            }
        }
        .sheet(item: $logsPod) { pod in
            PodLogsSheet(
                pod: pod.name,
                container: pod.containers.first,
                context: project?.kubeContext,
                namespace: project?.kubeNamespace ?? pod.namespace
            )
        }
    }

    // MARK: - Bound state

    @ViewBuilder
    private func content(_ project: Project) -> some View {
        VStack(spacing: 0) {
            header(project)
            Divider().background(Palette.divider)
            if loading && deployments.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, deployments.isEmpty {
                errorView(message: error)
            } else {
                HSplitView {
                    deploymentsTable
                        .frame(minWidth: 420)
                    detailPane(project)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Palette.bgBase)
                }
            }
        }
        .task(id: project.id) { await reload(project) }
    }

    private func header(_ project: Project) -> some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(Palette.cyan)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.kubeContext ?? "")
                    .font(Type.body)
                    .foregroundStyle(Palette.fgBright)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Namespace: \(project.kubeNamespace ?? "default")")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
            Spacer()
            Pill(text: "\(deployments.count) deployments", systemImage: "square.stack.3d.up", tint: Palette.fgMuted)
            Pill(text: "\(pods.count) pods", systemImage: "circle.grid.3x3", tint: Palette.fgMuted)
            Button {
                bindingSheet = true
            } label: {
                Label("Edit binding", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            Button {
                Task { await reload(project) }
            } label: {
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(loading)
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private var deploymentsTable: some View {
        Table(deployments, selection: $selectedDeploymentId) {
            TableColumn("Deployment") { d in
                Label {
                    Text(d.name).foregroundStyle(Palette.fgBright)
                } icon: {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundStyle(rolloutTint(d.status))
                }
            }
            .width(min: 180, ideal: 220)

            TableColumn("Status") { d in
                Pill(text: d.status.rawValue, tint: rolloutTint(d.status))
            }
            .width(110)

            TableColumn("Ready") { d in
                Text("\(d.readyReplicas)/\(d.replicas)")
                    .font(Type.monoCaption)
                    .foregroundStyle(d.readyReplicas == d.replicas ? Palette.green : Palette.orange)
            }
            .width(70)

            TableColumn("Image") { d in
                Text(d.image ?? "—")
                    .font(Type.monoCaption)
                    .foregroundStyle(Palette.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bgBase)
    }

    @ViewBuilder
    private func detailPane(_ project: Project) -> some View {
        if let id = selectedDeploymentId, let dep = deployments.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    deploymentHeader(dep, project: project)
                    podsSection(deployment: dep)
                    if !services.isEmpty {
                        servicesSection
                    }
                }
                .padding(Metrics.Space.lg)
            }
        } else {
            EmptyState(
                title: "Select a deployment",
                systemImage: "square.stack.3d.up",
                description: "Pick a deployment on the left to see its pods and actions.",
                tint: Palette.fgMuted
            )
        }
    }

    private func deploymentHeader(_ dep: K8sDeployment, project: Project) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(rolloutTint(dep.status))
                    .imageScale(.large)
                Text(dep.name)
                    .font(Type.title)
                    .foregroundStyle(Palette.fgBright)
                Spacer()
                Pill(text: dep.status.rawValue, tint: rolloutTint(dep.status))
                Pill(text: "\(dep.readyReplicas)/\(dep.replicas) ready", tint: Palette.fgMuted)
            }
            if let image = dep.image {
                Text(image)
                    .font(Type.mono)
                    .foregroundStyle(Palette.fgMuted)
                    .textSelection(.enabled)
            }
            HStack(spacing: Metrics.Space.sm) {
                Button {
                    Task { await restart(dep, project: project) }
                } label: {
                    Label("Restart rollout", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(actionInFlight)

                Button {
                    Task { await scale(dep, replicas: dep.replicas + 1, project: project) }
                } label: {
                    Label("+1 replica", systemImage: "plus.circle")
                }
                .disabled(actionInFlight)

                Button(role: .destructive) {
                    let target = max(0, dep.replicas - 1)
                    Task { await scale(dep, replicas: target, project: project) }
                } label: {
                    Label("-1 replica", systemImage: "minus.circle")
                }
                .disabled(actionInFlight || dep.replicas == 0)
            }
            if let error {
                Text(error)
                    .font(Type.caption)
                    .foregroundStyle(Palette.red)
                    .textSelection(.enabled)
            }
        }
    }

    private func podsSection(deployment: K8sDeployment) -> some View {
        let matching = pods.filter { $0.name.hasPrefix(deployment.name + "-") }
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Pods (\(matching.count))")
            if matching.isEmpty {
                Card { Text("No pods running.").foregroundStyle(Palette.fgMuted) }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(matching) { pod in
                            podRow(pod)
                            if pod.id != matching.last?.id {
                                Divider().background(Palette.divider)
                            }
                        }
                    }
                }
            }
        }
    }

    private func podRow(_ pod: K8sPod) -> some View {
        HStack(alignment: .top, spacing: Metrics.Space.md) {
            Image(systemName: "circle.fill")
                .foregroundStyle(podTint(pod.phase))
                .font(.system(size: 8))
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(pod.name)
                    .font(Type.mono)
                    .foregroundStyle(Palette.fgBright)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    if let node = pod.nodeName {
                        Label(node, systemImage: "cpu").labelStyle(.titleAndIcon)
                    }
                    if let ip = pod.podIP {
                        Label(ip, systemImage: "network").labelStyle(.titleAndIcon)
                    }
                    if pod.restartCount > 0 {
                        Label("\(pod.restartCount) restarts", systemImage: "arrow.clockwise")
                            .foregroundStyle(Palette.orange)
                    }
                }
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)
            }
            Spacer()
            Button {
                logsPod = pod
            } label: {
                Label("Logs", systemImage: "terminal")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Pill(text: pod.phase.rawValue, tint: podTint(pod.phase))
        }
        .padding(.horizontal, Metrics.Space.md)
        .padding(.vertical, Metrics.Space.sm)
    }

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Services")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(services) { svc in
                        serviceRow(svc)
                        if svc.id != services.last?.id {
                            Divider().background(Palette.divider)
                        }
                    }
                }
            }
        }
    }

    private func serviceRow(_ svc: K8sService) -> some View {
        HStack(alignment: .top, spacing: Metrics.Space.md) {
            Image(systemName: "network").foregroundStyle(Palette.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(svc.name).font(Type.body).foregroundStyle(Palette.fgBright)
                HStack(spacing: 8) {
                    Pill(text: svc.type, tint: Palette.fgMuted)
                    if let ip = svc.externalIP {
                        Text(ip).font(Type.monoCaption).foregroundStyle(Palette.fgMuted)
                    } else if let cluster = svc.clusterIP {
                        Text(cluster).font(Type.monoCaption).foregroundStyle(Palette.fgMuted)
                    }
                    if !svc.ports.isEmpty {
                        Text(svc.ports.joined(separator: ", "))
                            .font(Type.monoCaption)
                            .foregroundStyle(Palette.fgMuted)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, Metrics.Space.md)
        .padding(.vertical, Metrics.Space.sm)
    }

    // MARK: - Empty / error

    private func emptyState(_ project: Project) -> some View {
        VStack(spacing: Metrics.Space.lg) {
            EmptyState(
                title: "No cluster bound",
                systemImage: "shippingbox",
                description: "Bind this project to a kubectl context to see deployments, pods, and roll out restarts.",
                tint: Palette.cyan
            )
            Button {
                bindingSheet = true
            } label: {
                Label("Bind cluster…", systemImage: "link.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, Metrics.Space.xl)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: Metrics.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.orange)
                .font(.system(size: 32))
            Text("kubectl error")
                .font(Type.heading)
                .foregroundStyle(Palette.fgBright)
            Text(message)
                .font(Type.monoCaption)
                .foregroundStyle(Palette.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.Space.xl)
    }

    // MARK: - Loaders

    private func reload(_ project: Project) async {
        loading = true
        error = nil
        let ctx = project.kubeContext
        let ns = project.kubeNamespace
        do {
            async let depsTask = env.kubectl.deployments(context: ctx, namespace: ns)
            async let podsTask = env.kubectl.pods(context: ctx, namespace: ns)
            async let svcsTask = env.kubectl.services(context: ctx, namespace: ns)
            let (deps, pds, svcs) = try await (depsTask, podsTask, svcsTask)
            deployments = deps.sorted { $0.name < $1.name }
            pods = pds.sorted { $0.name < $1.name }
            services = svcs.sorted { $0.name < $1.name }
            if selectedDeploymentId == nil { selectedDeploymentId = deployments.first?.id }
        } catch {
            self.error = "\(error)"
        }
        loading = false
    }

    private func restart(_ dep: K8sDeployment, project: Project) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await env.kubectl.restartDeployment(
                name: dep.name, context: project.kubeContext, namespace: project.kubeNamespace
            )
            await reload(project)
        } catch {
            self.error = "\(error)"
        }
    }

    private func scale(_ dep: K8sDeployment, replicas: Int, project: Project) async {
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await env.kubectl.scaleDeployment(
                name: dep.name, replicas: replicas,
                context: project.kubeContext, namespace: project.kubeNamespace
            )
            await reload(project)
        } catch {
            self.error = "\(error)"
        }
    }

    // MARK: - Tints

    private func rolloutTint(_ status: K8sRolloutStatus) -> Color {
        switch status {
        case .healthy: return Palette.green
        case .progressing: return Palette.cyan
        case .degraded: return Palette.orange
        case .unknown: return Palette.fgMuted
        }
    }

    private func podTint(_ phase: K8sPodPhase) -> Color {
        switch phase {
        case .running, .succeeded: return Palette.green
        case .pending: return Palette.cyan
        case .failed: return Palette.red
        case .unknown: return Palette.fgMuted
        }
    }
}

// MARK: - Binding sheet

private struct KubeBindingSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ProjectListViewModel.self) private var projectList
    @Environment(\.dismiss) private var dismiss

    let project: Project

    @State private var contexts: [K8sContext] = []
    @State private var loading = true
    @State private var selectedContext: String = ""
    @State private var namespace: String = ""
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(Palette.cyan)
                Text("Bind Kubernetes context")
                    .font(Type.heading)
                    .foregroundStyle(Palette.fgBright)
                Spacer()
            }
            .padding(Metrics.Space.md)

            Divider().background(Palette.divider)

            Form {
                Section("Context") {
                    if loading {
                        ProgressView()
                    } else if contexts.isEmpty {
                        Text(loadError ?? "No contexts found in ~/.kube/config")
                            .foregroundStyle(Palette.fgMuted)
                    } else {
                        Picker("kubectl context", selection: $selectedContext) {
                            Text("Unset").tag("")
                            ForEach(contexts) { ctx in
                                Text(ctx.isCurrent ? "\(ctx.name) (current)" : ctx.name)
                                    .tag(ctx.name)
                            }
                        }
                    }
                }
                Section("Namespace") {
                    TextField("default", text: $namespace)
                }
                Section {
                    Text("Run `aws eks update-kubeconfig --name <cluster>` to add EKS contexts before binding.")
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    projectList.updateKubeBinding(
                        projectId: project.id,
                        context: selectedContext.isEmpty ? nil : selectedContext,
                        namespace: namespace.isEmpty ? nil : namespace
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(Metrics.Space.md)
        }
        .frame(width: 520, height: 480)
        .task { await loadContexts() }
        .onAppear {
            selectedContext = project.kubeContext ?? ""
            namespace = project.kubeNamespace ?? ""
        }
    }

    private func loadContexts() async {
        do {
            contexts = try await env.kubectl.contexts()
            loading = false
        } catch {
            loadError = "\(error)"
            loading = false
        }
    }
}
