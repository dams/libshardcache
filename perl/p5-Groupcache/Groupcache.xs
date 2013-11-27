#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <groupcache.h>

#include "const-c.inc"

#include <pthread.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static PerlInterpreter *orig_perl = NULL;

static inline int __acquire_lock() {
    int rc;
    int retries = 0;
    rc = pthread_mutex_trylock(&lock);
    while(rc != 0) {
        if (retries++ == 100) {
            return -1;
        }
        struct timespec tv = { 0, 10000000 }; // 10 ms
        struct timespec remainder = { 0, 0 };
        int ret;
        do {
            ret = nanosleep(&tv, &remainder);
            if (ret == -1) {
                memcpy(&tv, &remainder, sizeof(struct timespec));
                memset(&remainder, 0, sizeof(struct timespec));
            }
        } while (ret != 0);
        rc = pthread_mutex_trylock(&lock);
    }
    return 0;
}

static void *__st_fetch(void *key, size_t len, size_t *vlen, void *priv) {
    if (__acquire_lock() != 0) {
        fprintf(stderr, "__st_fetch can't acquire lock\n");
        return NULL;
    }
    PERL_SET_CONTEXT(orig_perl);
    dTHX;
    dSP;

    ENTER;
    SAVETMPS;

    SV *storage = (SV *)priv;
    SV *k = newSVpv(key, len);

    if (!sv_isobject(storage) || !sv_derived_from(storage, "Groupcache::Storage")) {
        croak("missing storage or not of class 'Groupcache::Storage'");
    }

    PUSHMARK(SP);
    XPUSHs(storage);
    XPUSHs(sv_2mortal(k));
    PUTBACK;

    int count = call_method("fetch", G_SCALAR);

    SPAGAIN;

    if (count != 1) {
        croak("Unexpected errors calling the 'fetch' method on the storage object");
    }

    SV *val = POPs;
    char * out = NULL;

    if (SvOK(val)) {
        STRLEN l;
        char *str = SvPVbyte(val, l);
        
        if (l) {
            Newx(out, l, char);
            memcpy(out, str, l);

            if (vlen)
                *vlen = l; 
        }
    }

    PUTBACK;
    FREETMPS;
    LEAVE;

    pthread_mutex_unlock(&lock);
    
    return (void *)out;
}

static void __st_store(void *key, size_t len, void *value, size_t vlen, void *priv) {
    if (__acquire_lock() != 0) {
        fprintf(stderr, "__st_store can't acquire lock\n");
        return;
    }
    PERL_SET_CONTEXT(orig_perl);
    dTHX;
    dSP;
    SV *storage = (SV *)priv;
    SV *k = newSVpv(key, len);
    SV *v = newSVpv(value, vlen);

    if (!sv_isobject(storage) || !sv_derived_from(storage, "Groupcache::Storage")) {
        croak("missing storage or not of class 'Groupcache::Storage'");
    }

    PUSHMARK(SP);
    XPUSHs(storage);
    XPUSHs(sv_2mortal(k));
    XPUSHs(sv_2mortal(v));
    PUTBACK;

    call_method("store", G_DISCARD);
    pthread_mutex_unlock(&lock);
}

static void __st_remove(void *key, size_t len, void *priv) {
    if (__acquire_lock() != 0) {
        fprintf(stderr, "__st_remove can't acquire lock\n");
        return;
    }
    PERL_SET_CONTEXT(orig_perl);
    dTHX;
    dSP;
    SV *storage = (SV *)priv;
    SV *k = newSVpv(key, len);

    if (!sv_isobject(storage) || !sv_derived_from(storage, "Groupcache::Storage")) {
        croak("missing storage or not of class 'Groupcache::Storage'");
    }

    PUSHMARK(SP);
    XPUSHs(storage);
    XPUSHs(sv_2mortal(k));
    PUTBACK;

    call_method("remove", G_DISCARD);
    pthread_mutex_unlock(&lock);
}

static void __st_free(void *val) {
    Safefree(val);
}

MODULE = Groupcache		PACKAGE = Groupcache		

INCLUDE: const-xs.inc

groupcache_t *
groupcache_create(me, peers, storage, secret)
        char *  me
        SV   *  peers
        SV   *  storage
        char *  secret
    PREINIT:
        int i;
	int	num_peers = 0;
        char ** shards = NULL;
    CODE:
        orig_perl = my_perl;
        if (!sv_isobject(storage) || !sv_derived_from(storage, "Groupcache::Storage")) {
            croak("missing storage or not of class 'Groupcache::Storage'");
        }
        
        if (peers) {
            if (!SvROK(peers) || SvTYPE(SvRV(peers)) != SVt_PVAV)
              croak("Expected an array reference as 'peers' parameter");

            AV *peers_array = (AV *)SvRV(peers);

            num_peers = av_len(peers_array) + 1;
            if (num_peers > 0) {
                Newx(shards, sizeof(char *) * num_peers + 1, char *);
                for (i = 0; i < num_peers; i++) {
                    STRLEN len;
                    char *peer;
                    SV **svp = av_fetch(peers_array, i, 0);
                    if (svp == NULL) {
                        // WRONG
                        len = 0;
                        peer = NULL;
                    } else {
                        peer = SvPVbyte(*svp, len);
                    }
                    shards[i] = peer;
                }
            }
        }

        groupcache_storage_t storage_struct = {
            .fetch  = __st_fetch,
            .store  = __st_store,
            .remove = __st_remove,
            .free   = __st_free,
            .priv   = SvREFCNT_inc(storage)
        };

        RETVAL = groupcache_create(me, shards, num_peers, &storage_struct, secret);
        if (shards)
            Safefree(shards);

        if (RETVAL == NULL)
            croak("Unknown error");

    OUTPUT:
        RETVAL

int
groupcache_del(cache, key, klen)
	groupcache_t *	cache
	char *	key
	size_t	klen
    CODE:
        int should_lock = 0;
        if (pthread_mutex_trylock(&lock) == EDEADLK)
            should_lock = 1;
        pthread_mutex_unlock(&lock);
        int ret = groupcache_del(cache, key, klen);
        if (should_lock)
            pthread_mutex_lock(&lock);
        RETVAL = ret;
    OUTPUT:
        RETVAL

void
groupcache_destroy(cache)
	groupcache_t *	cache

SV *
groupcache_get(cache, key, klen)
	groupcache_t *	cache
	char *	key
	size_t	klen
    PREINIT:
        size_t vlen = 0;
        const char *v = NULL;
    CODE:
        int should_lock = 0;
        if (pthread_mutex_trylock(&lock) == EDEADLK)
            should_lock = 1;
        pthread_mutex_unlock(&lock);
        v = groupcache_get(cache, key, klen, &vlen);
        if (should_lock)
            pthread_mutex_lock(&lock);
        RETVAL = v ? newSVpv(v, vlen) : &PL_sv_undef;
    OUTPUT:
        RETVAL

AV *
groupcache_get_peers(cache, num_peers)
	groupcache_t *	cache
	int *	num_peers
    PREINIT:
        int i;
        AV *peers;
    CODE:
        peers = newAV();
        char **list = groupcache_get_peers(cache, num_peers);
        for (i = 0; i < *num_peers; i++) {
            SV *peer = newSVpv(list[i], strlen(list[i]));
            av_push(peers, sv_2mortal(peer));
        }
        RETVAL = peers;
    OUTPUT:
        RETVAL

int
groupcache_set(cache, key, klen, value, vlen)
	groupcache_t *	cache
	char *	key
	size_t	klen
	char *	value
	size_t	vlen
    CODE:
        int should_lock = 0;
        if (pthread_mutex_trylock(&lock) == EDEADLK)
            should_lock = 1;
        pthread_mutex_unlock(&lock);
        int ret = groupcache_set(cache, key, klen, value, vlen);
        if (should_lock)
            pthread_mutex_lock(&lock);
        RETVAL = ret;
    OUTPUT:
        RETVAL

SV *
groupcache_test_ownership(cache, key, len)
	groupcache_t *	cache
	char *	key
	size_t	len
    PREINIT:
        const char *peer = NULL;
    CODE:
        groupcache_test_ownership(cache, key, len, &peer);
        if (peer) {
            RETVAL = newSVpv(peer, strlen(peer));
        } else {
            RETVAL = &PL_sv_undef;
        }
    OUTPUT:
        RETVAL

int 
groupcache_evict(cache, key, klen)
        groupcache_t *cache
        char *key
        size_t klen

SV *
groupcache_compute_signature(secret, msg)
        char *secret
        SV   *msg
    CODE:
        STRLEN l;
        char *ptr = SvPVbyte(msg, l);
        char key[16];
        strncpy(key, secret, sizeof(key));
        uint64_t digest = groupcache_compute_signature(key, (uint8_t *)ptr, l);
        RETVAL = newSViv(digest);
    OUTPUT:
        RETVAL

void
groupcache_run(coderef, timeout=1000, priv=&PL_sv_undef)
        SV *coderef
        IV timeout
        SV *priv
    CODE:
        struct timespec tv = { 1, 0 };
        if (!SvTRUE(coderef) || ! SvROK(coderef) || SvTYPE(SvRV(coderef)) != SVt_PVCV) {
            croak("missing coderef or not a CODE reference");
        }

        int secs = timeout/1000;
        int nsecs = (timeout%1000)*1000000;
        tv.tv_sec = secs;
        tv.tv_nsec = nsecs;

        /*
        PerlInterpreter *slave_perl = perl_clone(my_perl, CLONEf_KEEP_PTR_TABLE|CLONEf_COPY_STACKS);
        PERL_SET_CONTEXT(slave_perl);
        */
        for(;;) {
            struct timespec remainder = { 0, 0 };
            struct timespec tosleep = { tv.tv_sec, tv.tv_nsec };

            pthread_mutex_lock(&lock);

            dTHX;
            dSP;

            ENTER;
            SAVETMPS;

            PUSHMARK(SP);
            XPUSHs(priv);
            PUTBACK;

            int count = call_sv(coderef, G_SCALAR|G_EVAL);

            SPAGAIN;

            if (count != 1) {
                croak("Unexpected errors calling the registered runloop callback");
            }

            IV ret = POPi;

            PUTBACK;
            FREETMPS;
            LEAVE;

            pthread_mutex_unlock(&lock);

            if (ret == -1)  {
                // TODO - WARN
                break;
            }

            int rc;
            do {
                rc = nanosleep(&tosleep, &remainder);
                if (rc == -1) {
                    fprintf(stderr, "nanosleep exited: %s\n", strerror(errno));
                    memcpy(&tosleep, &remainder, sizeof(struct timespec));
                    memset(&remainder, 0, sizeof(struct timespec));
                }
            } while (rc != 0);
        }
        /*
        perl_free(slave_perl);
        PERL_SET_CONTEXT(orig_perl);        
        */

