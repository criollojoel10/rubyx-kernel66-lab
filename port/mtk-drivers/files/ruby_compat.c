// SPDX-License-Identifier: GPL-2.0
/*
 * Compatibilidad de ruby (Xiaomi) para los drivers que se compilan dentro de
 * la Image.
 *
 * El tactil Focaltech FT3680 y la huella Goodix son codigo de Xiaomi que
 * llama a dos ayudas que solo existen en el arbol de vendor de ruby:
 *
 *   - prize_common_node_register(): nodos /proc de "prize" para el gesto de
 *     doble toque y el FOD. Sin ella el driver no enlaza y el tactil no
 *     arranca.
 *   - mtk_drm_early_resume(): despierta el panel antes de tiempo para el
 *     desbloqueo con huella.
 *
 * En el arbol del A34 (GKI + device modules) no existe ninguna de las dos,
 * asi que se dan de alta aqui como no-ops: el tactil y la huella funcionan,
 * solo se pierden los nodos de prize y el despertar temprano del panel.
 */

#include <linux/kernel.h>
#include <linux/module.h>

/* Los drivers hablan con estas dos como si vivieran en otro modulo. */
void prize_common_node_register(char *name, void (*set)(unsigned char on_off));
int mtk_drm_early_resume(int timeout);

/*
 * Registro de nodos de prize. El driver solo lo usa para publicar el estado
 * del gesto; sin la infraestructura de Xiaomi no hay donde registrarlo.
 */
void prize_common_node_register(char *name, void (*set)(unsigned char on_off))
{
	pr_info("ruby-compat: nodo prize '%s' ignorado (sin infraestructura prize)\n",
		name ? name : "?");
}

/*
 * Despertar temprano del panel para el desbloqueo con huella. La buena
 * implementacion vive en el DRM de Xiaomi; aqui se devuelve exito para que
 * el driver siga su camino normal (el panel se despierta en el resume).
 */
int mtk_drm_early_resume(int timeout)
{
	return 0;
}
