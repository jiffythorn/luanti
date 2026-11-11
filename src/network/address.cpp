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
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <netdb.h>
#include <unistd.h>
#include <arpa/inet.h>
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
