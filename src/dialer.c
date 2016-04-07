#include <assert.h>
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <string.h>
#include <errno.h>


int levee_dialer_fds[2];
int levee_dialer_rc;


struct LeveeDialerRequest {
	uint16_t node_len;
	uint16_t service_len;
	uint16_t family;
	uint16_t socktype;
	uint8_t is_listening;
	int no;
};


struct LeveeDialerResponse {
	int err;
	int eai;
	int no;
};


void *
levee_dialer_loop (void *arg) {
	int rc;

	struct LeveeDialerRequest req;
	struct LeveeDialerResponse res;

	char node[256];
	char service[32];

	struct addrinfo hints, *info, *ptr;

	int no;
	int err;

	while (1) {
		memset (&res, 0, sizeof (res));
		memset (&hints, 0, sizeof (hints));

		rc = read (levee_dialer_fds[0], &req, sizeof (req));
		assert (rc == sizeof (req));
		assert (req.node_len < sizeof (node));
		assert (req.service_len < sizeof (service));

		rc = read (levee_dialer_fds[0], node, req.node_len);
		assert (rc == req.node_len);
		node[req.node_len] = 0;

		rc = read (levee_dialer_fds[0], service, req.service_len);
		assert (rc == req.service_len);
		service[req.service_len] = 0;

		hints.ai_family = req.family;
		hints.ai_socktype = req.socktype;

		rc = getaddrinfo (node, service, &hints, &info);
		if (rc != 0) {
			res.eai = rc;
			goto respond;
		}

		for (ptr = info; ptr; ptr = ptr->ai_next) {
			no = socket (ptr->ai_family, ptr->ai_socktype, ptr->ai_protocol);
			if (no < 0) {
				res.err = -errno;
				goto respond;
			}
			rc = connect (no, ptr->ai_addr, ptr->ai_addrlen);
			if (rc == 0) break;
			close (no);
			err = -errno;
		}

		freeaddrinfo (info);

		if (ptr == NULL) {
			res.err = err;
		} else {
			res.no = no;
		}

		respond:
		rc = write (req.no, &res, sizeof (res));
		assert (rc == sizeof (res));
	}
}


int levee_dialer_boot (void) {
	pthread_t thr;
	pthread_attr_t attr;
	int rc;

	rc = pipe (levee_dialer_fds);
	if (rc != 0) return -errno;

	rc = pthread_attr_init (&attr);
	if (rc != 0) return -errno;
	rc = pthread_attr_setdetachstate (&attr, PTHREAD_CREATE_DETACHED);
	if (rc != 0) return -errno;
	rc = pthread_create (&thr, &attr, &levee_dialer_loop, NULL);
	if (rc != 0) return -errno;

	return 0;
}


pthread_once_t levee_dialer_once = PTHREAD_ONCE_INIT;


void levee_dialer_run_once (void) {
	levee_dialer_rc = levee_dialer_boot ();
}


int levee_dialer_init (void) {
	pthread_once (&levee_dialer_once, levee_dialer_run_once);
	return levee_dialer_rc;
}


int
writer (const char *node, const char *service) {
	int rc;

	struct LeveeDialerRequest req;
	struct LeveeDialerResponse res;

	int fds[2];
	rc = pipe (fds);
	if (rc != 0) return -errno;

	memset (&req, 0, sizeof (req));
	req.node_len = (uint16_t) strlen (node);
	req.service_len = (uint16_t) strlen (service);
	req.socktype = SOCK_STREAM;
	req.family = AF_INET;
	req.no = fds[1];

	// Note: call should use writev to ensure the write is atomic
	rc = write (levee_dialer_fds[1], &req, sizeof (req));
	assert (rc == sizeof (req));
	rc = write (levee_dialer_fds[1], node, strlen (node));
	assert (rc == strlen (node));
	rc = write (levee_dialer_fds[1], service, strlen (service));
	assert (rc == strlen (service));

	rc = read (fds[0], &res, sizeof (res));
	assert (rc == sizeof (res));

	printf ("%s \\ %s \\ %d\n", gai_strerror (res.eai), strerror (res.err), res.no);
	return 0;
}


int main (int argc, char **argv)
{
	printf ("%lu\n", sizeof (struct LeveeDialerRequest));
	levee_dialer_init ();
	writer ("localhost", "8000");
	writer ("localhost", "8080");
	writer ("ldld", "8080");
	return 0;
}