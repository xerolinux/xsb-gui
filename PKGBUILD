# Maintainer: DarkXero <info@xerolinux.xyz>
pkgname=xsb-gui
pkgver=0.1.1
pkgrel=2
pkgdesc="XeroLinux Limine/SecureBoot Enabler"
arch=('x86_64')
url="https://github.com/xerolinux/xsb-gui"
license=('GPL-3.0-or-later')
depends=('python-pyqt6' 'polkit' 'sbctl' 'efibootmgr')
optdepends=('limine: installed automatically by xsb-helper migrate when you choose to migrate'
            'limine-mkinitcpio-hook: installed automatically by xsb-helper migrate when you choose to migrate')
install="${pkgname}.install"
source=()
sha256sums=()

package() {
    install -Dm755 "${srcdir}/../xsb-gui" "${pkgdir}/usr/bin/xsb-gui"
    install -Dm755 "${srcdir}/../xsb-helper" "${pkgdir}/usr/lib/xsb-gui/xsb-helper"
    install -d "${pkgdir}/usr/lib/xsb-gui/lib"
    install -Dm644 "${srcdir}/../lib/"*.sh "${pkgdir}/usr/lib/xsb-gui/lib/"
    local site_packages
    site_packages="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
    install -d "${pkgdir}${site_packages}/xsb_gui"
    cp -a "${srcdir}/../xsb_gui/." "${pkgdir}${site_packages}/xsb_gui/"
    install -Dm644 "${srcdir}/../xsb-gui.desktop" "${pkgdir}/usr/share/applications/xsb-gui.desktop"
    install -Dm644 "${srcdir}/../xyz.xerolinux.xsb-gui.policy" \
        "${pkgdir}/usr/share/polkit-1/actions/xyz.xerolinux.xsb-gui.policy"
    install -Dm644 "${srcdir}/../xsb_gui/assets/xsb-gui.png" \
        "${pkgdir}/usr/share/icons/hicolor/256x256/apps/xsb-gui.png"
}
