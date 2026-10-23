import SwiftUI

// Name the property-wrapper type explicitly. New SDKs also expose a State macro;
// this alias keeps the app compatible with command-line SDKs lacking that plugin.
typealias ViewState<Value> = SwiftUI.State<Value>
