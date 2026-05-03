//
//  ExarotonServerModel+HTTP.swift
//  OrzMC
//
//  Created by joker on 2024/5/20.
//

import ExarotonHTTP

extension ExarotonServerModel {
    @MainActor
    func fetchServers() async {
        guard let httpClient else { return }
        do {
            let response = try await httpClient.getServers()
            switch response {
            case .ok(let ok):
                if let data = try ok.body.json.data {
                    servers = data
                }
            default:
                break
            }
        } catch let error {
            errorMessage = "Failed to fetch Exaroton servers: \(error.localizedDescription)"
        }
    }

    func startServer(serverId: String) async -> Bool {
        guard let httpClient else { return false }
        do {
            let reponse = try await httpClient.getStartServer(path: .init(serverId: serverId))
            switch reponse {
            case .ok(let ok):
                let json = try ok.body.json
                let success = json.success ?? false
                statusMessage = success ? "Server start requested." : nil
                if !success {
                    errorMessage = "Exaroton did not accept the start request."
                }
                return success
            default:
                errorMessage = "Failed to start Exaroton server: unexpected response."
                return false
            }
        } catch let error {
            errorMessage = "Failed to start Exaroton server: \(error.localizedDescription)"
            return false
        }
    }

    func stopServer(serverId: String) async -> Bool {
        guard let httpClient else { return false }
        do {
            let reponse = try await httpClient.stopServer(path: .init(serverId: serverId))
            switch reponse {
            case .ok(let ok):
                let json = try ok.body.json
                let success = json.success ?? false
                statusMessage = success ? "Server stop requested." : nil
                if !success {
                    errorMessage = "Exaroton did not accept the stop request."
                }
                return success
            default:
                errorMessage = "Failed to stop Exaroton server: unexpected response."
                return false
            }
        } catch let error {
            errorMessage = "Failed to stop Exaroton server: \(error.localizedDescription)"
            return false
        }
    }

    func restartServer(serverId: String) async -> Bool {
        guard let httpClient else { return false }
        do {
            let reponse = try await httpClient.restartServer(path: .init(serverId: serverId))
            switch reponse {
            case .ok(let ok):
                let json = try ok.body.json
                let success = json.success ?? false
                statusMessage = success ? "Server restart requested." : nil
                if !success {
                    errorMessage = "Exaroton did not accept the restart request."
                }
                return success
            default:
                errorMessage = "Failed to restart Exaroton server: unexpected response."
                return false
            }
        } catch let error {
            errorMessage = "Failed to restart Exaroton server: \(error.localizedDescription)"
            return false
        }
    }

    func fetchCreditPools() async {
        guard let httpClient else { return }
        do {
            let response = try await httpClient.getCreditPools()
            switch response {
            case .ok(let ok):
                if let data = try ok.body.json.data {
                    creditPools = data
                }
            default:
                break
            }
        } catch let error {
            errorMessage = "Failed to fetch credit pools: \(error.localizedDescription)"
        }
    }

    func fetchCreditPoolInfo(_ pool: ExarotonCreditPool) async -> (ExarotonCreditPool?, [ExarotonCreditMember]?, [ExarotonServer]?)? {
        guard let poolId = pool.id
        else {
            return nil
        }
        guard let httpClient else {
            return nil
        }
        do {
            async let poolResponse = try await httpClient.getCreditPool(path: .init(poolId: poolId))
            async let membersResponse = try await httpClient.getCreditPoolMembers(path: .init(poolId: poolId))
            async let serversResponse = try await httpClient.getCreditPoolServers(path: .init(poolId: poolId))
            switch (try await poolResponse, try await membersResponse, try await serversResponse) {
            case (.ok(let poolOk), .ok(let membersOk), .ok(let serversOk)):
                let pool = try poolOk.body.json.data
                let members = try membersOk.body.json.data
                let servers = try serversOk.body.json.data
                return (pool, members, servers)
            default:
                return (nil, nil, nil)
            }
        } catch let error {
            errorMessage = "Failed to fetch credit pool info: \(error.localizedDescription)"
            return (nil, nil, nil)
        }
    }

    func getRAM(serverId: String) async -> Int32? {
        guard let httpClient else { return nil }
        do {
            let response = try await httpClient.getServerRam(path: .init(serverId: serverId))
            switch response {
            case .ok(let ok):
                let data = try ok.body.json.data
                if let ram = data?.ram {
                    statusMessage = "Server RAM changed to \(ram) GB."
                }
                return data?.ram
            default:
                errorMessage = "Failed to change server RAM: unexpected response."
                return nil
            }
        } catch {
            errorMessage = "Failed to fetch server RAM: \(error.localizedDescription)"
            return nil
        }
    }

    func changeRAM(serverId: String, ramGB: Int32) async -> Int32? {
        guard let httpClient else { return nil }
        do {
            let response = try await httpClient.postServerRam(path: .init(serverId: serverId), body: .json(.init(ram: ramGB)))
            switch response {
            case .ok(let ok):
                let data = try ok.body.json.data
                return data?.ram
            default:
                return nil
            }
        } catch {
            errorMessage = "Failed to change server RAM: \(error.localizedDescription)"
            return nil
        }
    }
}
