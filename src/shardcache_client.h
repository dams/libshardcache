#ifndef __SHARDCACHE_CLIENT_H__
#define __SHARDCACHE_CLIENT_H__

#include <shardcache.h>

#define SHARDCACHE_CLIENT_OK             0
#define SHARDCACHE_CLIENT_ERROR_NODE     1
#define SHARDCACHE_CLIENT_ERROR_NETWORK  2
#define SHARDCACHE_CLIENT_ERROR_ARGS     3

/**
 * @brief Opaque structure representing the shardcache client
 */
typedef struct shardcache_client_s shardcache_client_t;

/**
 * @brief Create a new shardcache client
 *
 * @param nodes           A list of <address:port> strings representing the nodes
 *                        taking part to the shardcache 'cloud'
 * @param num_nodes       The number of nodes present in the nodes list
 * @param auth            A null-terminated string containing the shared secret used to
 * @return A newly initialized shardcache client descriptor
 * @note The returned shardcache_client_t structure MUST be disposed using shardcache_client_destroy()
 */
shardcache_client_t *shardcache_client_create(shardcache_node_t *nodes, int num_nodes, char *auth);

/**
 * @brief Get the value for a key
 * @param c       A valid pointer to a shardcache_client_t structure
 * @param key     A valid pointer to the key
 * @param klen    The length of the key
 * @param data    A reference to the pointer which will be set to point to the memory
 *                holding the retrieved value
 *
 * @return the size of the memory pointed by *data, 0 if no data was found or in case of error
 * @note The caller can distinguish between 'no-data' and 'error' conditions by looking at the
 *       internal errno by using shardcache_client_errno()
 * @note The caller is responsible of releasing the memory pointed by *data (if any)
 * @note On success the internal errno will be set to SHARDCACHE_CLIENT_OK
 *
 * @see shardcache_client_errno()
 * @see shardcache_client_errstr()
 */
size_t shardcache_client_get(shardcache_client_t *c, void *key, size_t klen, void **data);

typedef void (*shardcache_client_get_aync_data_cb)(char *peer,
                                                   void *key,
                                                   size_t klen,
                                                   void *data,
                                                   size_t len,
                                                   void *priv);

int shardcache_client_get_async(shardcache_client_t *c,
                                void *key,
                                size_t klen,
                                shardcache_client_get_aync_data_cb data_cb,
                                void *priv);

/**
 * @brief Set the value for a key
 * @param c      A valid pointer to a shardcache_client_t structure
 * @param key    A valid pointer to the key
 * @param klen   The length of the key
 * @param data   A valid pointer to the value
 * @param dlen   The length of the value
 * @param expire The number of seconds after which the value should expire
 * @return 0 on success, -1 otherwise and the internal errno is set
 * @note On success the internal errno will be set to SHARDCACHE_CLIENT_OK
 * @see shardcache_client_errno()
 * @see shardcache_client_errstr()
 */
int shardcache_client_set(shardcache_client_t *c, void *key, size_t klen, void *data, size_t dlen, uint32_t expire);

/**
 * @brief Remove the value for a key
 * @param c     A valid pointer to a shardcache_client_t structure
 * @param key   A valid pointer to the key
 * @param klen  The length of the key
 * @return 0 on success, -1 otherwise the internal errno is set
 * @note On success the internal errno will be set to SHARDCACHE_CLIENT_OK
 * @see shardcache_client_errno()
 * @see shardcache_client_errstr()
 */
int shardcache_client_del(shardcache_client_t *c, void *key, size_t klen);

/**
 * @brief Evict (remove from the cache) the value for a key
 * @param c     A valid pointer to a shardcache_client_t structure
 * @param key   A valid pointer to the key
 * @param klen  The length of the key
 * @return 0 on success, -1 otherwise and the internal errno is set
 * @note On success the internal errno will be set to SHARDCACHE_CLIENT_OK
 * @see shardcache_client_errno()
 * @see shardcache_client_errstr()
 */
int shardcache_client_evict(shardcache_client_t *c, void *key, size_t klen);

/**
 * @brief Get the stats from a shardcache node
 * @param c     A valid pointer to a shardcache_client_t structure
 * @param node_name  The name of the node we want to get stats from
 * @param buf   A reference to the pointer which will be set to point to the memory
 *              holding the retrieved stats
 * @param len If not NULL, the size of memory pointed by *buf is stored in *len
 * @return 0 on success, -1 otherwise and the internal errno is set
 * @note The caller is responsible of releasing the memory eventually pointed by *buf
 *       by using free()
 * @note On success the internal errno will be set to SHARDCACHE_CLIENT_OK
 * @see shardcache_client_errno()
 * @see shardcache_client_errstr()
 */
int shardcache_client_stats(shardcache_client_t *c, char *node_name, char **buf, size_t *len);

/**
 * @brief Check the status of a shardcache node
 * @param c     A valid pointer to a shardcache_client_t structure
 * @param node_name  The name of the node we want to get stats from
 * @return 0 success, -1 otherwise and the internal errno is set
 * @note On success the internal errno will be set to SHARDCACHE_CLIENT_OK
 * @see shardcache_client_errno()
 * @see shardcache_client_errstr()
 */
int shardcache_client_check(shardcache_client_t *c, char *node_name);

/**
 * @brief Start a migration
 * @param c     A valid pointer to a shardcache_client_t structure
 * @param nodes           A list of <address:port> strings representing the nodes
 *                        taking part to the shardcache 'cloud'
 * @param num_nodes       The number of nodes present in the nodes list
 * @return 0 success, -1 otherwise and the internal errno is set
 * @note On success the internal errno will be set to SHARDCACHE_CLIENT_OK
 * @see shardcache_client_errno()
 * @see shardcache_client_errstr()
 */
int shardcache_client_migration_begin(shardcache_client_t *c, shardcache_node_t *nodes, int num_nodes);

/**
 * @brief Abort the current migration (if any)
 * @param c     A valid pointer to a shardcache_client_t structure
 * @return 0 success, -1 otherwise and the internal errno is set
 * @note On success the internal errno will be set to SHARDCACHE_CLIENT_OK
 * @see shardcache_client_errno()
 * @see shardcache_client_errstr()
 */
int shardcache_client_migration_abort(shardcache_client_t *c);


/**
 * @brief Get the index from a shardcache node
 * @param c     A valid pointer to a shardcache_client_t structure
 * @param node_name  The name of the node we want to get stats from
 * @return 0 success, -1 otherwise
 * @note The caller must use shardcache_free_index() to release memory used
 *       by the returned shardcache_storage_index_t pointer
 * @note On success the internal errno will be set to SHARDCACHE_CLIENT_OK
 * @see shardcache_client_errno()
 * @see shardcache_client_errstr()
 */
shardcache_storage_index_t *shardcache_client_index(shardcache_client_t *c, char *node_name);

/**
 * @brief Return the error code for the last operation performed by the shardcache client
 * @param c     A valid pointer to a shardcache_client_t structure
 * @return The errno
 * @see shardcache_client_errno()
 */
int shardcache_client_errno(shardcache_client_t *c);

/**
 * @brief Return the error string for the last operation performed by the shardcache client
 * @param c     A valid pointer to a shardcache_client_t structure
 * @return The error string
 * @see shardcache_client_errno()
 */
char *shardcache_client_errstr(shardcache_client_t *c);

/**
 * @brief Release all the resources used by the shardcache client instance
 * @param c     A valid pointer to a shardcache_client_t structure to release
 */
void shardcache_client_destroy(shardcache_client_t *c);

#endif
