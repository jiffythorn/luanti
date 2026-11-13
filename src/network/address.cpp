// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2013 celeron55, Perttu Ahola <celeron55@gmail.com>

#include "address.h"

#include <iostream>
#include <cstring>
#include <cerrno>
#include "network/networkexceptions.h"
#include "settings.h"

#ifdef _WIN32
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#define LAST_SOCKET_ERR() WSAGetLastError()
typedef SOCKET socket_t;
typedef int socklen_t;
#else
#include <algorithm>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <netdb.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#ifdef __ANDROID__
// bionic only declares getifaddrs() from API 24, and the phone app supports
// older Android, so interface lookup goes through the kernel instead.
#include <sys/ioctl.h>
#include <linux/sockios.h>
#endif
#define LAST_SOCKET_ERR() (errno)
typedef int socket_t;
#endif

/*
	Address
*/

Address::Address()
{
	memset(&m_address, 0, sizeof(m_address));
}

Address::Address(u32 address, u16 port)
{
	memset(&m_address, 0, sizeof(m_address));
	setAddress(address);
	setPort(port);
}

Address::Address(u8 a, u8 b, u8 c, u8 d, u16 port)
{
	memset(&m_address, 0, sizeof(m_address));
	setAddress(a, b, c, d);
	setPort(port);
}

Address::Address(const IPv6AddressBytes *ipv6_bytes, u16 port)
{
	memset(&m_address, 0, sizeof(m_address));
	setAddress(ipv6_bytes);
	setPort(port);
}

// Equality (address family, IP and port must be equal)
bool Address::operator==(const Address &other) const
{
	if (other.m_addr_family != m_addr_family || other.m_port != m_port)
		return false;

	if (m_addr_family == AF_INET) {
		return m_address.ipv4.s_addr == other.m_address.ipv4.s_addr;
	}

	if (m_addr_family == AF_INET6) {
		return memcmp(m_address.ipv6.s6_addr,
				other.m_address.ipv6.s6_addr, 16) == 0;
	}

	return false;
}

void Address::Resolve(const char *name, Address *fallback)
{
	if (!name || name[0] == 0) {
		if (m_addr_family == AF_INET)
			setAddress(static_cast<u32>(0));
		else if (m_addr_family == AF_INET6)
			setAddress(static_cast<IPv6AddressBytes*>(nullptr));
		if (fallback)
			*fallback = Address();
		return;
	}

	const auto &copy_from_ai = [] (const struct addrinfo *ai, Address *to) {
		if (ai->ai_family == AF_INET) {
			struct sockaddr_in *t = (struct sockaddr_in *)ai->ai_addr;
			to->m_addr_family = AF_INET;
			to->m_address.ipv4 = t->sin_addr;
		} else if (ai->ai_family == AF_INET6) {
			struct sockaddr_in6 *t = (struct sockaddr_in6 *)ai->ai_addr;
			to->m_addr_family = AF_INET6;
			to->m_address.ipv6 = t->sin6_addr;
		} else {
			to->m_addr_family = 0;
		}
	};

	struct addrinfo hints;
	memset(&hints, 0, sizeof(hints));

	// set a type, so every unique address is only returned once
	hints.ai_socktype = SOCK_DGRAM;
	if (g_settings->getBool("enable_ipv6")) {
		// AF_UNSPEC allows both IPv6 and IPv4 addresses to be returned
		hints.ai_family = AF_UNSPEC;
	} else {
		hints.ai_family = AF_INET;
	}
	hints.ai_flags = AI_ADDRCONFIG;

	// Do getaddrinfo()
	struct addrinfo *resolved = nullptr;
	int e = getaddrinfo(name, nullptr, &hints, &resolved);
	if (e != 0)
		throw ResolveError(gai_strerror(e));
	assert(resolved);

	// Copy data
#ifdef LOCAL_NETWORK_ONLY
	// Phone-client build: only the home network is allowed. Pick the first
	// local address the resolver returned, and refuse a public one outright,
	// so a typed internet address or a hostname that resolves outside the
	// LAN cannot take the app off the local network.
	bool found_local = false;
	for (struct addrinfo *ai = resolved; ai; ai = ai->ai_next) {
		Address candidate;
		copy_from_ai(ai, &candidate);
		if (candidate.isLocalNetwork()) {
			// Resolve() must preserve the port supplied to this Address
			// (the server port), not replace it with the candidate's
			// default port 0.
			candidate.setPort(m_port);
			*this = candidate;
			found_local = true;
			break;
		}
	}
	if (!found_local) {
		freeaddrinfo(resolved);
		throw ResolveError("This app only joins servers on the local network");
	}
	if (fallback)
		*fallback = Address();
#else
	copy_from_ai(resolved, this);
	if (fallback) {
		*fallback = Address();
		if (resolved->ai_next)
			copy_from_ai(resolved->ai_next, fallback);
	}
#endif

	freeaddrinfo(resolved);
}

// IP address -> textual representation
std::string Address::serializeString() const
{
	const void *src = nullptr;
	switch (m_addr_family) {
		case AF_INET:  src = &m_address.ipv4; break;
		case AF_INET6: src = &m_address.ipv6; break;
	}

	if (!src)
		return "<unhandled-addr-family>";

	char str[INET6_ADDRSTRLEN];
	if (inet_ntop(m_addr_family, src, str, sizeof(str)) == nullptr)
		return "";
	return str;
}

bool Address::isAny() const
{
	if (m_addr_family == AF_INET) {
		return m_address.ipv4.s_addr == 0;
	} else if (m_addr_family == AF_INET6) {
		static const char zero[16] = {0};
		return memcmp(m_address.ipv6.s6_addr, zero, 16) == 0;
	}

	return false;
}

void Address::setAddress(u32 address)
{
	m_addr_family = AF_INET;
	m_address.ipv4.s_addr = htonl(address);
}

void Address::setAddress(u8 a, u8 b, u8 c, u8 d)
{
	u32 addr = (a << 24) | (b << 16) | (c << 8) | d;
	setAddress(addr);
}

void Address::setAddress(const IPv6AddressBytes *ipv6_bytes)
{
	m_addr_family = AF_INET6;
	if (ipv6_bytes)
		memcpy(m_address.ipv6.s6_addr, ipv6_bytes->bytes, 16);
	else
		memset(m_address.ipv6.s6_addr, 0, 16);
}

void Address::setPort(u16 port)
{
	m_port = port;
}

void Address::print(std::ostream& s) const
{
	if (m_addr_family == AF_INET6)
		s << "[" << serializeString() << "]:" << m_port;
	else if (m_addr_family == AF_INET)
		s << serializeString() << ":" << m_port;
	else
		s << "(undefined)";
}

bool Address::isLocalNetwork() const
{
	if (m_addr_family == AF_INET) {
		u32 addr = ntohl(m_address.ipv4.s_addr);
		// 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8,
		// 169.254.0.0/16 and the unspecified address.
		return (addr >> 24) == 10 ||
			(addr >> 20) == 0xAC1 ||
			(addr >> 16) == 0xC0A8 ||
			(addr >> 24) == 127 ||
			(addr >> 16) == 0xA9FE ||
			addr == 0;
	}

	if (m_addr_family == AF_INET6) {
		const u8 *a = m_address.ipv6.s6_addr;
		static const u8 loopback[16] = {
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1};
		static const u8 mapped[12] = {
			0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF};

		if (memcmp(a, loopback, 16) == 0)
			return true;
		// IPv6 link-local (fe80::/10) and unique-local (fc00::/7).
		if (a[0] == 0xFE && (a[1] & 0xC0) == 0x80)
			return true;
		if ((a[0] & 0xFE) == 0xFC)
			return true;
		// IPv4-mapped address: check the embedded IPv4 address.
		if (memcmp(a, mapped, 12) == 0) {
			Address v4(a[12], a[13], a[14], a[15], 0);
			return v4.isLocalNetwork();
		}
	}

	return false;
}

bool Address::isBroadcast() const
{
	return m_addr_family == AF_INET &&
		m_address.ipv4.s_addr == INADDR_BROADCAST;
}

#ifndef _WIN32
// Append one interface's subnet broadcast, skipping loopback and degenerate
// addresses that cannot reach the town PC.
static void add_subnet_broadcast(std::vector<Address> &result, u32 broadcast,
		u16 port)
{
	if (broadcast == 0 || broadcast == 0xFFFFFFFFu)
		return;

	Address candidate(
		static_cast<u8>((broadcast >> 24) & 0xFF),
		static_cast<u8>((broadcast >> 16) & 0xFF),
		static_cast<u8>((broadcast >> 8) & 0xFF),
		static_cast<u8>(broadcast & 0xFF), port);
	if (!candidate.isLocalNetwork())
		return;
	if (std::find(result.begin(), result.end(), candidate) == result.end())
		result.push_back(candidate);
}
#endif

std::vector<Address> Address::getLocalIPv4BroadcastAddresses(u16 port)
{
	std::vector<Address> result;
#ifdef _WIN32
	// The phone client is the target for this fallback. Windows LAN clients
	// keep using the limited broadcast above.
	(void)port;
#elif defined(__ANDROID__)
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	if (fd < 0)
		return result;

	char buf[4096];
	struct ifconf ifc;
	ifc.ifc_len = sizeof(buf);
	ifc.ifc_buf = buf;
	if (ioctl(fd, SIOCGIFCONF, &ifc) == 0) {
		for (char *p = buf; p + sizeof(struct ifreq) <= buf + ifc.ifc_len;
				p += sizeof(struct ifreq)) {
			const auto *entry = reinterpret_cast<const struct ifreq *>(p);

			struct ifreq ifr;
			memset(&ifr, 0, sizeof(ifr));
			memcpy(ifr.ifr_name, entry->ifr_name, IFNAMSIZ - 1);

			if (ioctl(fd, SIOCGIFFLAGS, &ifr) != 0)
				continue;
			if (!(ifr.ifr_flags & IFF_UP) ||
					(ifr.ifr_flags & IFF_LOOPBACK) ||
					!(ifr.ifr_flags & IFF_BROADCAST))
				continue;

			if (ioctl(fd, SIOCGIFBRDADDR, &ifr) != 0)
				continue;
			const auto *broadcast = reinterpret_cast<const sockaddr_in *>(
				&ifr.ifr_broadaddr);
			if (broadcast->sin_family != AF_INET)
				continue;

			add_subnet_broadcast(result,
				ntohl(broadcast->sin_addr.s_addr), port);
		}
	}
	close(fd);
#else
	struct ifaddrs *interfaces = nullptr;
	if (getifaddrs(&interfaces) != 0)
		return result;

	for (struct ifaddrs *ifa = interfaces; ifa; ifa = ifa->ifa_next) {
		if (!(ifa->ifa_flags & IFF_UP) ||
				(ifa->ifa_flags & IFF_LOOPBACK))
			continue;
		if (!ifa->ifa_addr || !ifa->ifa_netmask ||
				ifa->ifa_addr->sa_family != AF_INET)
			continue;

		const auto *addr = reinterpret_cast<const sockaddr_in *>(
			ifa->ifa_addr);
		const auto *mask = reinterpret_cast<const sockaddr_in *>(
			ifa->ifa_netmask);
		u32 ip = ntohl(addr->sin_addr.s_addr);
		u32 netmask = ntohl(mask->sin_addr.s_addr);
		if (netmask == 0 || netmask == 0xFFFFFFFFu)
			continue;

		add_subnet_broadcast(result, ip | ~netmask, port);
	}
	freeifaddrs(interfaces);
#endif
	return result;
}

bool Address::isLocalhost() const
{
	if (m_addr_family == AF_INET6) {
		static const u8 localhost_bytes[] = {
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1};
		static const u8 mapped_ipv4_localhost[] = {
				0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 0x7f, 0, 0, 0};

		auto *addr = m_address.ipv6.s6_addr;

		return memcmp(addr, localhost_bytes, 16) == 0 ||
			memcmp(addr, mapped_ipv4_localhost, 13) == 0;
	} else if (m_addr_family == AF_INET) {
		auto addr = ntohl(m_address.ipv4.s_addr);
		return (addr >> 24) == 0x7f;
	}
	return false;
}
