#include "shardcache_replica.h"
#include <hashtable.h>
#include <linklist.h>
#include <queue.h>
#include "atomic.h"

#define SHARDCACHE_REPLICA_WRKDIR_DEFAULT "/tmp/shcrpl"

struct __shardcache_replica_message_s {
    shardcache_hdr_t hdr;
};

typedef struct __shardcache_replica_node_s {
    uint32_t seq;
    linked_list_t *messages;
    shardcache_replica_status_t status;
    shardcache_replica_role_t role;
    char *addr;
} shardcache_replica_node_t;

typedef struct __shardcache_replica_view_s {
    uint32_t id;
    int num_addresses;
    char **addresses;
} shardcache_replica_view_t;

typedef enum {
    SHARDCACHE_REPLICA_CMD_STATUS_UNSTABLE,
    SHARDCACHE_REPLICA_CMD_STATUS_STABLE
} shardcache_replica_command_status_t;

struct __shardcache_replica_command_s {
    shardcache_replica_event_t evt;
    shardcache_replica_operation_t op;
    shardcache_record_t *records;
    int num_records;
    uint32_t view_id;
    shardcache_replica_command_status_t status;
    shardcache_replica_node_t *acked;
    int num_acked;
};

struct __shardcache_replica_s {
    shardcache_t *shc;
    queue_t *cmd_queue;
    shardcache_node_t *node;
    hashtable_t *status;
    char *me;
    int num_replicas;
    shardcache_replica_view_t *current_view;
    shardcache_replica_view_t *last_view;
#ifdef __MACH__
    OSSpinLock view_lock;
#else
    pthread_spinlock_t view_lock;
#endif
    pthread_t replicator;
    int quit;
};

static int build_current_view(hashtable_t *table, void *value, size_t vlen, void *priv)
{
    shardcache_replica_view_t *view = (shardcache_replica_view_t *)priv;
    shardcache_replica_node_t *node = (shardcache_replica_node_t *)value;
    if (node->status == SHARDCACHE_REPLICA_STATUS_ONLINE) {
        view->addresses = realloc(view->addresses, sizeof(char *) * (view->num_addresses + 1));
        view->addresses[view->num_addresses++] = node->addr;
    }
    if (view->num_addresses >= ht_count(table))
        return 0;
    return 1;
}

void
shardcache_replica_install_view(shardcache_replica_t *replica, shardcache_replica_view_t *view)
{
}

shardcache_replica_view_t *
shardcache_replica_current_view(shardcache_replica_t *replica)
{
    shardcache_replica_view_t *view = calloc(1, sizeof(shardcache_replica_view_t));
    SPIN_LOCK(&replica->view_lock);
    view->id = replica->current_view->id + 1;
    ht_foreach_value(replica->status, build_current_view, view);
    if (view->num_addresses == replica->current_view->num_addresses) {
        int i;
        for (i = 0; i < view->num_addresses; i++) {
            if (strcmp(view->addresses[i], replica->current_view->addresses[i]) != 0) {
                // the views differ
                
            }
        }
    }
    free(view->addresses);
    free(view);
    SPIN_UNLOCK(&replica->view_lock);
    return replica->current_view;
}

static void *
replicator(void *priv)
{
    shardcache_replica_t *replica = (shardcache_replica_t *)priv;
    while(!ATOMIC_READ(replica->quit)) {
        // handle new commands
        shardcache_replica_command_t *cmd = queue_pop_left(replica->cmd_queue);
        while (cmd) {
            // do something with cmd
            cmd = queue_pop_left(replica->cmd_queue);

            switch(cmd->evt) {
                case SHARDCACHE_REPLICA_RECEIVE:
                    break;
                case SHARDCACHE_REPLICA_SEND:
                    break;
                default:
                    // TODO - Error Messages
                    break;
            }
        }
        // let's now check the status and resend failed commands
    }
    return NULL;
}

shardcache_replica_node_t *
shardcache_replica_node_create(char *addr)
{
    shardcache_replica_node_t *node = calloc(1, sizeof(shardcache_replica_node_t));
    node->addr = strdup(addr);
    node->messages = create_list();
    return node;
}
 
static void
shardcache_replica_node_destroy(shardcache_replica_node_t *node)
{
    free(node->addr);
    destroy_list(node->messages);
    free(node);
}

shardcache_replica_t *
shardcache_replica_create(shardcache_t *shc,
                          shardcache_node_t *node,
                          char *me,
                          char *wrkdir)
{
    shardcache_replica_t *replica = calloc(1, sizeof(shardcache_replica_t));

    replica->cmd_queue = queue_create();
    queue_set_free_value_callback(replica->cmd_queue,
            (queue_free_value_callback_t)shardcache_replica_command_destroy);

    replica->node = shardcache_node_copy(node);

    int rc = pthread_create(&replica->replicator, NULL, replicator, replica);
    if (rc != 0) {
        queue_destroy(replica->cmd_queue);
        shardcache_node_destroy(replica->node);
        free(replica);
        return NULL;
    }

    replica->me = strdup(me);

    replica->num_replicas = shardcache_node_num_addresses(node);

    replica->status = ht_create(replica->num_replicas, 128, (ht_free_item_callback_t)shardcache_replica_node_destroy);

    int i;
    for (i = 0; i < replica->num_replicas; i ++) {
        char *addr = shardcache_node_get_address_at_index(node, i);
        if (addr) {
            shardcache_replica_node_t *rnode = shardcache_replica_node_create(addr);
            rc = ht_set(replica->status, addr, strlen(addr), rnode, sizeof(shardcache_replica_node_t));
            if (rc != 0) {
                // TODO - Error messages
            }
        }
    }

    SPIN_INIT(&replica->view_lock);

    replica->shc = shc;

    return replica;
}

void
shardcache_replica_destroy(shardcache_replica_t *replica)
{
    ATOMIC_INCREMENT(replica->quit);
    pthread_join(replica->replicator, NULL);
    queue_destroy(replica->cmd_queue);
    ht_destroy(replica->status);
    shardcache_node_destroy(replica->node);
    free(replica->me);
    SPIN_DESTROY(&replica->view_lock);
    if (replica->current_view) {
        free(replica->current_view->addresses);
        free(replica->current_view);
    }
    if (replica->last_view) {
        free(replica->last_view->addresses);
        free(replica->last_view);
    }
    free(replica);
}


shardcache_replica_command_t *
shardcache_replica_command_create(shardcache_replica_event_t evt,
                                  shardcache_replica_operation_t op,
                                  shardcache_record_t *records,
                                  int num_records)
{
    shardcache_replica_command_t *cmd = calloc(1, sizeof(shardcache_replica_command_t));
    cmd->evt = evt;
    cmd->op = op;
    cmd->records = malloc(sizeof(shardcache_record_t) * num_records);
    int i;
    for (i = 0; i < num_records; i++) {
        cmd->records[i].v = malloc(records[i].l);
        memcpy(cmd->records[i].v, records[i].v, records[i].l);
        cmd->records[i].l = records[i].l;
    }
    cmd->num_records = num_records;
    return cmd;
}

void
shardcache_replica_command_destroy(shardcache_replica_command_t *cmd)
{
    int i;
    for (i = 0; i < cmd->num_records; i++)
        free(cmd->records[i].v);
    free(cmd->records);
    free(cmd);
}

shardcache_replica_status_t
shardcache_replica_status(shardcache_replica_t *replica, char *addr)
{
    shardcache_replica_node_t *node = ht_get(replica->status, addr, strlen(addr), NULL);
    if (!node)
        return SHARDCACHE_REPLICA_STATUS_UNKNOWN;

    return node->status;
}

shardcache_replica_status_t
shardcache_replica_set_status(shardcache_replica_t *replica,
                              char *addr,
                              shardcache_replica_status_t status)
{
    shardcache_replica_node_t *node = ht_get(replica->status, addr, strlen(addr), NULL);
    if (!node)
        return SHARDCACHE_REPLICA_STATUS_UNKNOWN;

    shardcache_replica_status_t st = node->status;
    node->status = status;
    return st;
}